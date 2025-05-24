defmodule Buzy.Llm do
  require Logger
  import Buzy.Llm.Helpers, only: [trigger_callback: 3]

  alias Buzy.Config
  alias Buzy.Llm.{Execution, Message, Clients, Response, Error}

  alias Buzy.Llm.Config.Model, as: ModelCfg

  @type t :: %__MODULE__{
          # validation_errors: [Phase.Error.t()],
          # result: nil | Result.Object.t(),
          # Llm: Llm.t(),
          # private: %{},
          # halted: halted
        }

  # @derive Jason.Encoder
  defstruct [
    # :provider,
    :model,
    # :client,
    :response_mime_type,
    :response_format,
    :candidate_count,
    # :response_schema,
    # :name,
    # :metadata,
    # :messages,
    # :response_format,
    # :functions,
    # :function_call,
    # :presence_penalty,
    # :frequency_penalty,
    :temperature,
    :thinking_budget,
    :context,
    stream: false,
    tools: [],
    callbacks: [],
    plugins: []
    # :max_tokens,
    # :selected_sources
  ]

  def new!(model) when is_binary(model), do: new!(model: model)

  def new!(opts) when is_list(opts) do
    # todo validate
    struct!(__MODULE__, opts)
  end

  def call(llm, message_or_messages, opts \\ [])

  def call(%__MODULE__{} = llm, %Message{} = message, opts) do
    call(llm, [message], opts)
  end

  @step1 :exec_plugins_before_call
  @step2 :get_model_cfg
  @step3 :get_client_structured_format
  @step4 :build_client_parms
  @step5 :call_client
  @step6 :parse_and_validate_response
  def call(%__MODULE__{} = llm, messages, opts) when is_list(messages) do
    llm =
      llm
      |> maybe_merge_context(opts)
      |> maybe_merge_callbacks(opts)
      |> merge_plugins(opts)
      |> maybe_enable_streaming()

    # todo
    # check_config()

    with {@step1, %Execution{llm: llm, response: nil} = execution} <-
           {@step1,
            trigger_plugins(llm.plugins, :before_call, %Execution{llm: llm, messages: messages})},
         {@step2, %ModelCfg{client: client, client_opts: client_opts}} <-
           {@step2, Config.model(llm.model)},
         {@step3, structured_format} <-
           {@step3, apply(client, :structured_format, [])},
         {@step4, {:ok, parms}} <-
           {@step4, Clients.Parms.build(llm, structured_format, execution.private)},
         {@step5, {:ok, %Response{} = resp}} <-
           {@step5,
            apply(client, :call, [
              parms,
              execution.messages,
              Keyword.merge(client_opts || [], opts)
            ])},
         {@step6, %Response{valid: true} = resp} <-
           {@step6, Response.parse(resp, llm, structured_format)} do
      handle_response(%{execution | response: resp, private: resp.private})
    else
      {@step1, %Execution{response: %Response{private: private} = resp} = execution}
      when is_nil(private) or map_size(private) == 0 ->
        handle_response(%{execution | response: %{resp | private: execution.private}})

      {@step1, %Execution{response: %Response{}} = execution} ->
        handle_response(execution)

      {@step2, %ModelCfg{client: nil}} ->
        Logger.warning(fn ->
          [inspect(__MODULE__), " Client config not found for model ", llm.model]
        end)

        {:error,
         %Error{
           reason: :model_config_not_found,
           message: "Client config not found for model #{llm.model}"
         }}

      {@step4, {:error, reson}} ->
        # Logger.warning(fn ->
        #   [
        #     inspect(__MODULE__),
        #     " error calling llm with client=",
        #     inspect(client),
        #     " client_code=",
        #     Integer.to_string(code),
        #     " reason=",
        #     reason
        #   ]
        # end)

        {:error, reson}

      {@step5, {:error, %Error{code: code, reason: reason} = error}} ->
        %ModelCfg{client: client} = Config.model(llm.model)

        Logger.warning(fn ->
          [
            inspect(__MODULE__),
            " error calling llm with client=",
            inspect(client),
            " client_code=",
            inspect(code),
            " reason=",
            inspect(reason)
          ]
        end)

        {:error, error}

      {_step, error} ->
        error
    end
  end

  defp handle_response(%Execution{llm: llm, response: %Response{valid: nil} = resp} = execution) do
    %ModelCfg{client: client} = Config.model(llm.model)
    structured_format = apply(client, :structured_format, [])
    handle_response(%{execution | response: Response.parse(resp, llm, structured_format)})
  end

  defp handle_response(%Execution{llm: llm, response: %Response{valid: true} = resp} = execution) do
    execution =
      trigger_plugins(llm.plugins, :after_call, %{
        execution
        | response: resp,
          private: resp.private
      })

    # don't want to send the private plugin state to callbacks as could be across processes
    trigger_callback(llm.callbacks, :on_llm_end, Map.put(resp, :private, nil))

    {:ok, %{resp | private: execution.private}}
  end

  # todo decide how rety should be handled on a structured_format error
  defp handle_response(%Execution{llm: llm, response: %Response{valid: false} = resp} = execution) do
    execution =
      trigger_plugins(llm.plugins, :after_call, %{
        execution
        | response: resp,
          private: resp.private
      })

    # don't want to send the private plugin state to callbacks as could be across processes
    trigger_callback(llm.callbacks, :on_llm_end, Map.put(resp, :private, nil))

    {:ok, %{resp | private: execution.private}}
  end

  def hydrate_response(%__MODULE__{} = llm, responses) when is_list(responses) do
    Enum.reduce_while(responses, [], fn resp, acc ->
      case hydrate_response(llm, resp) do
        %Response{} = resp -> {:cont, [resp | acc]}
        {:error, reason} -> {:halt, reason}
      end
    end)
    |> then(fn
      [_first | _rest] = responses -> Enum.reverse(responses)
      error -> error
    end)
  end

  @step1 :build_client_parms
  @step2 :hydrate_response
  @step3 :parse_and_validate_response
  def hydrate_response(%__MODULE__{model: model} = llm, response) when is_map(response) do
    %ModelCfg{client: client} = Config.model(model)
    structured_format = apply(client, :structured_format, [])

    with {@step1, {:ok, params}} <-
           {@step1, Clients.Parms.build(llm, structured_format)},
         {@step2, %Response{} = resp} <-
           {@step2, apply(client, :hydrate, [params, response])},
         {@step3, %Response{valid: true} = resp} <-
           {@step3, Response.parse(resp, llm, structured_format)} do
      resp
    end
  end

  def set_temperature(%__MODULE__{} = llm, temperature) do
    %__MODULE__{llm | temperature: temperature}
  end

  def add_response_mime_type(%__MODULE__{} = llm, type) do
    %__MODULE__{llm | response_mime_type: type}
  end

  def add_response_format(%__MODULE__{} = llm, fmt) do
    %__MODULE__{llm | response_format: fmt}
  end

  def add_callback(%__MODULE__{callbacks: callbacks} = llm, new_callbacks)
      when is_list(new_callbacks) do
    %__MODULE__{llm | callbacks: new_callbacks ++ callbacks}
  end

  def add_callback(%__MODULE__{callbacks: callbacks} = llm, callback) do
    %__MODULE__{llm | callbacks: [callback | callbacks]}
  end

  def add_tools(%__MODULE__{tools: tools} = llm, new_tools) when is_list(new_tools) do
    %__MODULE__{llm | tools: new_tools ++ tools}
  end

  def add_tools(%__MODULE__{tools: tools} = llm, tool) do
    %__MODULE__{llm | tools: [tool | tools]}
  end

  def add_context(%__MODULE__{} = llm, context) do
    %__MODULE__{llm | context: context}
  end

  def set_candidate_count(%__MODULE__{} = llm, candidate_count) do
    %__MODULE__{llm | candidate_count: candidate_count}
  end

  def client_base_url(%__MODULE__{model: model}, opts \\ []) do
    Config.model(model).client.base_url(opts)
  end

  defp maybe_merge_callbacks(%__MODULE__{callbacks: callbacks} = llm, opts) do
    callbacks = callbacks ++ Keyword.get(opts, :callbacks, [])
    %__MODULE__{llm | callbacks: callbacks}
  end

  defp merge_plugins(%__MODULE__{plugins: plugins} = llm, opts) do
    plugins = (Keyword.get(opts, :plugins, []) ++ plugins ++ Config.plugins()) |> Enum.uniq()
    %__MODULE__{llm | plugins: plugins}
  end

  defp maybe_merge_context(%__MODULE__{context: nil} = llm, opts) do
    %__MODULE__{llm | context: opts[:context]}
  end

  defp maybe_merge_context(%__MODULE__{context: context} = llm, opts) do
    context = Map.merge(context, opts[:context] || %{})
    %__MODULE__{llm | context: context}
  end

  # currently don't stream when response is structured output as this requires stream parsing the json
  defp maybe_enable_streaming(%__MODULE__{response_format: nil, stream: false} = llm) do
    %__MODULE__{llm | stream: has_streaming_callbacks?(llm)}
  end

  defp maybe_enable_streaming(llm), do: llm

  defp has_streaming_callbacks?(%__MODULE__{callbacks: callbacks}) do
    !(callbacks |> Enum.filter(&(elem(&1, 0) == :on_llm_new_token)) |> Enum.empty?())
  end

  defp trigger_plugins([], _fn_call, execution) do
    execution
  end

  defp trigger_plugins(plugins, fn_call, execution) when fn_call in [:before_call, :after_call] do
    Enum.reduce(plugins, execution, fn plugin, acc ->
      Code.ensure_loaded(plugin)

      if function_exported?(plugin, fn_call, 1) do
        apply(plugin, fn_call, [acc])
      else
        acc
      end
    end)
  end
end
