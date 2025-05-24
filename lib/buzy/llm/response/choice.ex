defmodule Buzy.Llm.Response.Choice do
  alias Buzy.Llm
  alias Buzy.Llm.Response.Part
  alias Buzy.Llm.Clients.StructuredFormat

  defstruct [
    :finish_reason,
    :parts
  ]

  def build(chunk) do
    %__MODULE__{
      finish_reason: chunk["finish_reason"],
      parts: chunk["parts"]
    }
  end

  def parse(%__MODULE__{} = choice, %Llm{} = llm, %StructuredFormat{} = structured_fmt) do
    parsed =
      for %Part{type: type} = part when type in [:text, :tool_call] <- choice.parts do
        Part.parse(part, llm, structured_fmt)
      end

    %{choice | parts: parsed}
  end

  def errors(%__MODULE__{parts: parts}) do
    for %{error: error} when not is_nil(error) <- parts do
      error
    end
  end

  def parsed_content(%__MODULE__{parts: parts}) do
    for %{parsed_content: content} when not is_nil(content) <- parts do
      content
    end
  end

  def first_parsed_content(%__MODULE__{parts: parts}) do
    Enum.find_value(parts, fn
      %{parsed_content: nil} -> nil
      %{parsed_content: content} -> content
    end)
  end

  def first_content(choices) when is_list(choices) do
    Enum.find_value(choices, &first_content/1)
  end

  def first_content(%__MODULE__{parts: parts}) do
    for %{type: :text, content: content} when is_binary(content) <- parts, into: "", do: content
  end

  def first_tool_call(choices) when is_list(choices) do
    Enum.find_value(choices, &first_tool_call/1)
  end

  def first_tool_call(%__MODULE__{parts: parts}) do
    Enum.find_value(parts, fn
      %{type: :tool_call, content: tool_call} -> tool_call
      _ -> nil
    end)
  end

  def tool_calls(choices) when is_list(choices) do
    for choice <- choices,
        %Part{type: :tool_call, content: tool_call} <- choice.parts do
      tool_call
    end
  end

  def tool_calls(_choices), do: []

  def first_finish_reason(choices) when is_list(choices) do
    Enum.find_value(choices, & &1.finish_reason)
  end

  def finished?(choices) when is_list(choices) do
    Enum.all?(choices, &__MODULE__.finished?/1)
  end

  def finished?(%__MODULE__{finish_reason: nil}), do: false
  def finished?(%__MODULE__{finish_reason: _reason}), do: true

  def merge(nil, r), do: r

  def merge([%__MODULE__{} = l], [%__MODULE__{} = r]) do
    [merge(l, r)]
  end

  def merge(
        %__MODULE__{parts: l_parts} = l,
        %__MODULE__{finish_reason: nil, parts: r_parts}
      ) do
    %{l | parts: Part.merge(l_parts, r_parts, false)}
  end

  def merge(
        %__MODULE__{parts: l_parts} = l,
        %__MODULE__{finish_reason: finish_reason, parts: r_parts}
      ) do
    %{
      l
      | finish_reason: finish_reason,
        parts: Part.merge(l_parts, r_parts, true)
    }
  end
end
