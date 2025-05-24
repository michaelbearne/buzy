# https://platform.openai.com/docs/api-reference/chat

defmodule Buzy.Llm.Clients.Openai.Chat do
  use ReqClientBase, service_name: :openai
  import Buzy.Llm.Clients.Helpers

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  import Buzy.Llm.Clients.Openai.Helpers

  alias Buzy.Config
  alias Buzy.Llm.{Response, Error}
  alias Buzy.Llm.Clients.Parms
  alias Buzy.Llm.Clients.StructuredFormat

  @default_base_url "https://api.openai.com"
  @default_path "/v1/chat/completions"
  @structured_format %StructuredFormat{type: :json_schema, wrap_array_in_object: true}

  def base_url(opts) do
    Keyword.get(opts, :base_url, Config.openai_base_url() || @default_base_url)
  end

  def url_path(opts) do
    Keyword.get(opts, :url_path, Config.openai_url_path() || @default_path)
  end

  def api_key(opts) do
    Keyword.get(opts, :api_key, Config.openai_api_key())
  end

  def structured_format, do: @structured_format

  def headers(api_key) do
    [{"Content-Type", "application/json"}, {"Authorization", "Bearer #{api_key}"}]
  end

  @span_name "buzy.llm.clients.openai.call"
  def call(%Parms{model: _model, stream: stream} = params, messages, opts \\ []) do
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
          headers: headers(api_key(opts)),
          base_url: base_url(opts),
          url: url_path(opts),
          body: JSON.encode!(request_params)
        ]
        |> Keyword.merge(opts)
        |> post()
        |> build_response(params)
        |> tap(fn
          {:ok, %Response{model: model, usage: usage} = _r} ->
            Tracer.set_attributes(%{
              "llm.provider": "openai",
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
      choices: build_choices(resp["candidates"]),
      usage: %Response.Usage{
        completion_tokens: resp["usageMetadata"]["candidatesTokenCount"] || 0,
        prompt_tokens: resp["usageMetadata"]["promptTokenCount"],
        total_tokens: resp["usageMetadata"]["totalTokenCount"]
        #  total_price: Pricing.calc_price(resp)
      }
    }
  end

  defp build_chunked_resp(%Parms{} = parms, [%{"error" => error}]) do
    %{"code" => code, "message" => message, "status" => reason} = error
    Error.build(200, message: message, reason: reason, model: parms.model, code: code)
  end

  defp build_chunked_resp(%Parms{} = parms, chunk) do
    %Response.Chunk{
      model: chunk["modelVersion"] || parms.model,
      choices: build_choices(chunk["candidates"]),
      usage: %Response.Usage{
        completion_tokens: chunk["usageMetadata"]["candidatesTokenCount"] || 0,
        prompt_tokens: chunk["usageMetadata"]["promptTokenCount"],
        total_tokens: chunk["usageMetadata"]["totalTokenCount"]
        #  total_price: Pricing.calc_price(resp)
      }
    }
  end

  defp build_request_params(%Parms{} = parms, messages, opts) do
    temperature_supported = Keyword.get(opts, :temperature_supported, true)

    messages =
      messages
      |> List.wrap()
      |> Enum.map(&%{"role" => map_role(&1.role), "content" => &1.content})

    params =
      %{
        messages: messages,
        model: parms.model,
        response_format:
          if(parms.response_format,
            do: %{
              type: "json_schema",
              # json_schema: %{name: "list_response", schema: parms.response_format}
              json_schema: parms.response_format
            }
          ),
        # tools: prompt.functions,
        # tool_calls: prompt.function_call,
        temperature:
          if(temperature_supported, do: Keyword.get(opts, :temperature, parms.temperature || 0))
        # presence_penalty: Keyword.get(opts, :presence_penalty, prompt.presence_penalty),
        # frequency_penalty: Keyword.get(opts, :frequency_penalty, prompt.frequency_penalty),
        # max_tokens: Keyword.get(opts, :max_tokens, prompt.max_tokens)
        # stream: if(opts[:into], do: true, else: nil)
      }
      # |> Enum.reject(&(elem(&1, 1) == nil))
      |> Map.reject(&is_nil(elem(&1, 1)))

    {:ok, params}
  end

  @span_name "buzy.llm.openai.clients.build_response"

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
          %{"code" => code, "message" => message, "type" => type} = error

          dbg(error)

          {:error,
           Error.build(status, message: message, reason: type, model: parms.model, code: code)}

        resp ->
          {:ok,
           %Response{
             model: resp["model"] || parms.model,
             choices: build_choices(resp["choices"]),
             usage: %Response.Usage{
               completion_tokens: resp["usage"]["completion_tokens"] || 0,
               prompt_tokens: resp["usage"]["prompt_tokens"],
               total_tokens: resp["usage"]["total_tokens"]
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

  defp build_choices(choices) when is_list(choices) do
    Enum.map(choices, &build_choice/1)
  end

  defp build_choices(choices), do: choices

  defp build_choice(%{"message" => message, "finish_reason" => finish_reason}) do
    %Response.Choice{finish_reason: map_finish_reason(finish_reason), parts: build_parts(message)}
  end

  defp build_choice(choice), do: choice

  defp build_parts(%{"content" => content}) do
    [Response.Part.build(:text, content)]
  end
end
