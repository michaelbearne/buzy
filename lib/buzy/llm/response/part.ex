defmodule Buzy.Llm.Response.Part do
  alias Buzy.Llm
  alias Buzy.Llm.Response.ToolCall
  alias Buzy.Llm.Clients.StructuredFormat

  defstruct [:type, :content, :parsed_content, :error]

  def build(:tool_call, call) do
    %__MODULE__{
      type: :tool_call,
      content: ToolCall.build(call)
    }
  end

  def build(type, content) do
    %__MODULE__{
      type: type,
      content: content
    }
  end

  def parse(
        %__MODULE__{type: :text} = part,
        %Llm{response_format: response_schema},
        %StructuredFormat{} = structured_fmt
      )
      when is_map(response_schema) or is_tuple(response_schema) do
    with {:ok, _schema} <-
           Peri.validate_schema(response_schema),
         {:ok, parsed} <-
           JSON.decode(part.content),
         unwraped <-
           Peri.maybe_unwrap_data(parsed,
             schema_type: structured_fmt.type,
             wrap_array_in_object: structured_fmt.wrap_array_in_object
           ),
         {:ok, _resp} <-
           Peri.validate(response_schema, unwraped) do
      %{part | parsed_content: unwraped}
    else
      {:error, reason} ->
        # todo map to step and test errors
        %{part | error: reason}
    end
  end

  def parse(
        %__MODULE__{type: :tool_call} = part,
        %Llm{tools: [_first | _rest] = tools},
        %StructuredFormat{} = _structured_fmt
      ) do
    %{content: %{name: name, args: args}} = part
    tool = Enum.find(tools, &(&1.name == name))

    if tool do
      parameters_schema = Map.get(tool, :parameters)

      if parameters_schema do
        with {:ok, _schema} <- Peri.validate_schema(parameters_schema),
             {:ok, _resp} <- Peri.validate(parameters_schema, args) do
          part
        else
          {:error, reason} ->
            # todo map to step and test errors
            %{part | error: reason}
        end
      else
        part
      end
    else
      %{part | error: "called tool #{name} not configured"}
    end
  end

  def parse(%__MODULE__{} = part, _response_schema, _structured_fmt) do
    part
  end

  def merge(l, r, finished \\ false)

  def merge(
        [%__MODULE__{type: :text, content: l_content} = l],
        [%__MODULE__{type: :text, content: r_content}],
        false
      )
      when is_binary(l_content) do
    [%{l | content: [r_content, l_content]}]
  end

  def merge(
        [%__MODULE__{type: :text, content: l_content} = l],
        [%__MODULE__{type: :text, content: r_content}],
        false
      ) do
    [%{l | content: [r_content | l_content]}]
  end

  def merge(
        [%__MODULE__{type: :text, content: l_content} = l],
        [%__MODULE__{type: :text, content: r_content}],
        true
      ) do
    content = [r_content | l_content] |> Enum.reverse() |> IO.iodata_to_binary()
    [%{l | content: content}]
  end

  def merge(l, [r], false) do
    [r | l]
  end

  def merge(l, [r], true) do
    [r | l]
    |> Enum.reverse()
    |> Enum.map(fn
      %{type: :text, content: content} = part ->
        %{part | content: content |> Enum.reverse() |> IO.iodata_to_binary()}

      part ->
        part
    end)
  end
end
