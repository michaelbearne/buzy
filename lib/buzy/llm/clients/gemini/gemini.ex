# https://aistudio.google.com/plan_information
# https://ai.google.dev/gemini-api/docs/text-generation?lang=rest

defmodule Buzy.Llm.Clients.Gemini do
  use ReqClientBase, service_name: :gemini
  import Buzy.Llm.Clients.Helpers

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  import __MODULE__.Helpers

  alias Buzy.Config
  alias Buzy.Llm.{Response, Message, Error}
  alias Buzy.Llm.Clients.Parms
  alias Buzy.Llm.Clients.StructuredFormat

  @default_base_url "https://generativelanguage.googleapis.com"
  @default_api_version "v1beta"
  @structured_format %StructuredFormat{type: :open_api}

  def base_url(opts) do
    Keyword.get(opts, :base_url, Config.google_ai_base_url() || @default_base_url)
  end

  def api_key(opts) do
    Keyword.get(opts, :api_key, Config.google_ai_api_key())
  end

  def api_version(opts) do
    Keyword.get(opts, :api_version, Config.google_ai_api_version() || @default_api_version)
  end

  def structured_format, do: @structured_format

  def headers, do: [{"Content-Type", "application/json"}]

  @span_name "buzy.llm.clients.gemini.call"
  def call(%Parms{model: model, stream: stream} = params, messages, opts \\ []) do
    Tracer.with_span @span_name do
      opts =
        if stream do
          stream_fn =
            handle_stream_fn(
              params,
              &decode_stream/1,
              &build_chunked_resp(params, &1)
            )

          Keyword.put(opts, :into, stream_fn)
        else
          opts
        end

      with {:ok, request_params} <- build_request_params(params, messages, opts) do
        [
          headers: headers(),
          base_url: base_url(opts),
          url: "/#{api_version(opts)}/models/#{model}:#{get_action(params)}?key=#{api_key(opts)}",
          body: JSON.encode!(request_params)
        ]
        |> Keyword.merge(opts)
        |> post()
        |> build_response(params)
        |> tap(fn
          {:ok, %Response{model: model, usage: usage} = _r} ->
            Tracer.set_attributes(%{
              "llm.provider": "gemini",
              "llm.model": model
            })

            if usage do
              Tracer.set_attributes(%{
                "llm.usage.completion_tokens": usage.completion_tokens,
                "llm.usage.prompt_tokens": usage.prompt_tokens,
                "llm.usage.total_tokens": usage.total_tokens
                # "llm.usage.total_price": usage.total_price && Decimal.to_float(usage.total_price)
              })
            end

          _error ->
            # noop
            nil
        end)
      end
    end
  end

  def hydrate(%Parms{model: model}, resp) do
    %Response{
      model: resp["modelVersion"] || model,
      choices: build_candidates(resp["candidates"]),
      usage: %Response.Usage{
        completion_tokens: resp["usageMetadata"]["candidatesTokenCount"] || 0,
        prompt_tokens: resp["usageMetadata"]["promptTokenCount"],
        total_tokens: resp["usageMetadata"]["totalTokenCount"]
        #  total_price: Pricing.calc_price(resp)
      }
    }
  end

  defp get_action(%Parms{stream: false}), do: "generateContent"
  defp get_action(%Parms{stream: true}), do: "streamGenerateContent"

  defp build_chunked_resp(%Parms{} = parms, [%{"error" => error}]) do
    %{"code" => code, "message" => message, "status" => reason} = error
    Error.build(200, message: message, reason: reason, model: parms.model, code: code)
  end

  defp build_chunked_resp(%Parms{} = parms, chunk) do
    %Response.Chunk{
      model: chunk["modelVersion"] || parms.model,
      choices: build_candidates(chunk["candidates"]),
      usage: %Response.Usage{
        completion_tokens: chunk["usageMetadata"]["candidatesTokenCount"] || 0,
        prompt_tokens: chunk["usageMetadata"]["promptTokenCount"],
        total_tokens: chunk["usageMetadata"]["totalTokenCount"]
        #  total_price: Pricing.calc_price(resp)
      }
    }
  end

  defp build_request_params(%Parms{} = parms, messages, opts) do
    # https://ai.google.dev/gemini-api/docs/thinking
    thinking_budget_supported = Keyword.get(opts, :thinking_budget_supported, true)

    parms =
      if !thinking_budget_supported && parms.thinking_budget do
        Logger.warning(fn ->
          ["Thinking budget not supported for ", parms.model, " removing parms"]
        end)

        %{parms | thinking_budget: nil}
      else
        parms
      end

    messages = List.wrap(messages)
    first_system_msg_idx = Enum.find_index(messages, &(&1.role == :system))

    {system_msg, messages} =
      if first_system_msg_idx do
        List.pop_at(messages, first_system_msg_idx)
      else
        {nil, messages}
      end

    contents = messages |> List.wrap() |> Enum.map(&build_request_message/1)

    params =
      %{
        "system_instruction" => system_msg && %{"parts" => %{"text" => system_msg.content}},
        "contents" => contents,
        # todo
        # "safetySettings" =>
        "generationConfig" =>
          %{
            "temperature" => Keyword.get(opts, :temperature, parms.temperature || 0),
            # "topP" => google_ai.top_p,
            # "topK" => google_ai.top_k,
            "candidateCount" => parms.candidate_count,
            "response_mime_type" => response_mime_type(parms),
            "response_schema" => parms.response_format,
            "thinkingConfig" =>
              if(parms.thinking_budget, do: %{"thinkingBudget" => parms.thinking_budget})
          }
          |> Map.reject(&is_nil(elem(&1, 1))),
        "tools" =>
          [
            %{
              # Google AI functions use an OpenAI compatible format.
              # See: https://ai.google.dev/docs/function_calling#how_it_works
              "functionDeclarations" => parms.tools
            }
            |> Map.reject(&(is_nil(elem(&1, 1)) || Enum.empty?(elem(&1, 1))))
          ]
          |> Enum.reject(&(is_nil(&1) || Enum.empty?(&1)))
      }
      |> Map.reject(&(is_nil(elem(&1, 1)) || Enum.empty?(elem(&1, 1))))

    {:ok, params}
  end

  defp build_request_message(%Message{role: role, content: content, tool_calls: tool_calls})
       when is_binary(content) and is_list(tool_calls) do
    %{
      "role" => map_role(role),
      "parts" => [%{"text" => content} | build_tool_calls_parts(tool_calls)]
    }
  end

  defp build_request_message(%Message{role: role, content: content}) when is_binary(content) do
    %{"role" => map_role(role), "parts" => [%{"text" => content}]}
  end

  defp build_request_message(%Message{role: role, content: nil, tool_calls: tool_calls})
       when is_list(tool_calls) do
    %{"role" => map_role(role), "parts" => build_tool_calls_parts(tool_calls)}
  end

  defp build_request_message(%Message{role: role, content: nil, tool_results: tool_results})
       when is_list(tool_results) do
    %{"role" => map_role(role), "parts" => build_tool_results_parts(tool_results)}
  end

  defp build_request_message(%Message{role: role, content: content, tool_results: tool_results})
       when is_binary(content) and is_list(tool_results) do
    %{
      "role" => map_role(role),
      "parts" => [%{"text" => content} | build_tool_results_parts(tool_results)]
    }
  end

  defp build_tool_calls_parts(tool_calls) do
    Enum.map(tool_calls, &%{"functionCall" => %{"name" => &1.name, "args" => &1.args}})
  end

  defp build_tool_results_parts(tool_results) do
    Enum.map(
      tool_results,
      &%{
        "functionResponse" => %{
          "name" => &1.name,
          "response" => %{
            "name" => &1.name,
            "content" => &1.response
          }
        }
      }
    )
  end

  defp response_mime_type(%Parms{response_mime_type: type}) when is_binary(type) do
    type
  end

  # when no mime_type set and have a response_format it is assumed it is json
  defp response_mime_type(%Parms{response_format: fmt, response_mime_type: nil})
       when is_map(fmt) do
    "application/json"
  end

  defp response_mime_type(%Parms{response_mime_type: nil}), do: nil

  # # todo handal "finish_reason": "length",

  @span_name "buzy.llm.gemini.clients.build_response"

  # returned when streamed as an accumulation of the streamed chunks
  defp build_response({:ok, %Req.Response{status: status, body: %Response{} = resp}}, _parms)
       when status == 200
       when status == 201
       when status == 202 do
    {:ok, resp}
  end

  # returned when stream errors
  defp build_response({:ok, %Req.Response{body: %Error{} = error}}, _parms) do
    {:error, error}
  end

  defp build_response({:ok, %Req.Response{status: status, body: resp} = _req_resp}, parms)
       when status == 200
       when status == 201
       when status == 202 do
    Tracer.with_span @span_name do
      resp = if is_binary(resp), do: JSON.decode!(resp)

      case resp do
        %{"error" => error} ->
          %{"code" => code, "message" => message, "status" => reason} = error

          {:error,
           Error.build(status, message: message, reason: reason, model: parms.model, code: code)}

        resp ->
          {:ok,
           %Response{
             model: resp["modelVersion"] || parms.model,
             choices: build_candidates(resp["candidates"]),
             usage: %Response.Usage{
               completion_tokens: resp["usageMetadata"]["candidatesTokenCount"] || 0,
               prompt_tokens: resp["usageMetadata"]["promptTokenCount"],
               total_tokens: resp["usageMetadata"]["totalTokenCount"]
               #  total_price: Pricing.calc_price(resp)
             }
           }}
      end
    end
  end

  defp build_response({:ok, %Req.Response{status: status, body: ""}}, _parms)
       when status >= 400 do
    {:error, Error.build(status, message: "Unable to process chunked request")}
  end

  defp build_response({:ok, %Req.Response{status: status, body: resp}}, parms)
       when status >= 400 do
    Tracer.with_span @span_name do
      case JSON.decode(resp) do
        {:ok, %{"error" => error}} ->
          Logger.warning(fn ->
            [
              "Server error calling Openai message: ",
              error["message"],
              " status: ",
              Integer.to_string(status)
            ]
          end)

          {:error,
           Error.build(status,
             model: error["model"] || (parms.model && Atom.to_string(parms.model)),
             message: "Unable to process request",
             provider_message: error["message"],
             provider_code: error["code"],
             provider_type: error["type"]
           )}

        {:error, _decode_reason} ->
          Logger.warning(fn ->
            [
              "Server error calling Openai message: ",
              resp,
              " status: ",
              Integer.to_string(status)
            ]
          end)

          {:error,
           Error.build(status,
             message: "Unable to process request",
             provider_message: resp
           )}
      end
    end
  end

  defp build_response({:error, %Req.TransportError{reason: :timeout}}, _parms) do
    {:error, Error.build(nil, message: "request timeout", reason: :timeout)}
  end

  defp build_response({:error, %Req.TransportError{reason: reason}}, _parms) do
    {:error, Error.build(nil, message: "transport " <> Atom.to_string(reason), reason: reason)}
  end

  defp build_response({:error, %RuntimeError{message: message}}, _parms) do
    {:error, Error.build(nil, message: message, reason: :timeout)}
  end

  defp build_candidates(candidates) when is_list(candidates) do
    Enum.map(candidates, &build_candidate/1)
  end

  defp build_candidates(candidates), do: candidates

  defp build_candidate(%{"content" => %{"parts" => parts}, "finishReason" => finish_reason}) do
    %Response.Choice{finish_reason: map_finish_reason(finish_reason), parts: build_parts(parts)}
  end

  defp build_candidate(%{"content" => %{"parts" => parts}}) do
    %Response.Choice{parts: build_parts(parts)}
  end

  defp build_candidate(%{"finishReason" => finish_reason}) do
    %Response.Choice{finish_reason: map_finish_reason(finish_reason), parts: []}
  end

  defp build_candidate(candidate), do: candidate

  defp build_parts([%{"text" => content} | rest]) do
    [Response.Part.build(:text, content) | build_parts(rest)]
  end

  defp build_parts([%{"functionCall" => call} | rest]) do
    [Response.Part.build(:tool_call, call) | build_parts(rest)]
  end

  defp build_parts([]), do: []
end
