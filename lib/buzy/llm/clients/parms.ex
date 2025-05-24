defmodule Buzy.Llm.Clients.Parms do
  alias Buzy.Llm
  alias Buzy.Llm.Clients.StructuredFormat

  # @derive Jason.Encoder
  defstruct [
    :model,
    :response_mime_type,
    :response_format,
    :candidate_count,
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
    callbacks: [],
    plugins: [],
    tools: [],
    private: %{},
    stream: false
    # :max_tokens,
    # :selected_sources
  ]

  @step1 :validate_and_convert_response_format
  @step2 :validate_and_convert_tools
  def build(%Llm{} = llm, %StructuredFormat{} = structured_fmt, private \\ %{}) do
    with {@step1, {:ok, response_format}} <-
           {@step1, convert_response_format(llm, structured_fmt)},
         {@step2, {:ok, tools}} <-
           {@step2, convert_tools(llm, structured_fmt)} do
      {:ok,
       %__MODULE__{
         model: llm.model,
         response_mime_type: llm.response_mime_type,
         response_format: response_format,
         candidate_count: llm.candidate_count,
         temperature: llm.temperature,
         thinking_budget: llm.thinking_budget,
         context: llm.context,
         callbacks: Enum.filter(llm.callbacks, &(elem(&1, 0) == :on_llm_new_token)),
         plugins: llm.plugins,
         private: private,
         tools: tools,
         stream: llm.stream
       }}
    else
      {@step1, {:error, reson}} ->
        {:error, {@step1, reson}}

      {@step2, {:error, reson}} ->
        {:error, {@step2, reson}}

      {_step, error} ->
        dbg(error)
        error
    end
  end

  defp convert_response_format(%Llm{response_format: nil}, _structured_format) do
    {:ok, nil}
  end

  defp convert_response_format(%Llm{response_format: schema}, structured_fmt) do
    with {:ok, _schema} <- Peri.validate_schema(schema) do
      case structured_fmt.type do
        :open_api ->
          {
            :ok,
            Peri.to_open_api(schema)
          }

        :json_schema ->
          {:ok,
           Peri.to_json_schema(
             schema,
             wrap_array_in_object: structured_fmt.wrap_array_in_object
           )}

        type ->
          {
            :error,
            {:schema_type_not_supported, type}
          }
      end
    end
  end

  defp convert_tools(%Llm{tools: nil}, _structured_fmt), do: {:ok, []}
  defp convert_tools(%Llm{tools: []}, _structured_fmt), do: {:ok, []}

  defp convert_tools(
         %Llm{tools: tools},
         %StructuredFormat{type: required_schema_type} = structured_fmt
       ) do
    if required_schema_type in [:open_api, :json_schema] do
      converted_tools = Enum.map(tools, &convert_tool(&1, structured_fmt))
      errors = Enum.filter(converted_tools, &(is_tuple(&1) && elem(&1, 0) == :error))

      if Enum.empty?(errors) do
        {:ok, converted_tools}
      else
        {:error, Enum.map(errors, &elem(&1, 1))}
      end
    else
      {:error, {:schema_type_not_supported, required_schema_type}}
    end
  end

  defp convert_tool(
         %{name: name, parameters: parameters} = tool,
         %StructuredFormat{type: required_schema_type} = structured_fmt
       ) do
    case {Peri.validate_schema(parameters), required_schema_type} do
      {{:ok, _schema}, :open_api} ->
        %{tool | parameters: Peri.to_open_api(parameters)}

      {{:ok, _schema}, :json_schema} ->
        %{
          tool
          | parameters:
              Peri.to_json_schema(parameters,
                wrap_array_in_object: structured_fmt.wrap_array_in_object
              )
        }

      {{:error, errors}, _type} ->
        {:error, %{tool: name, parameters_errors: errors}}
    end
  end

  defp convert_tool(tool, _structured_fmt), do: tool
end
