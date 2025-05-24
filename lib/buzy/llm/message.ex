defmodule Buzy.Llm.Message do
  defstruct [:content, :tool_calls, :tool_results, role: :user]

  def system(content) when is_binary(content) do
    %__MODULE__{role: :system, content: clean_white_space(content)}
  end

  def system(%__MODULE__{} = msg) do
    %__MODULE__{msg | role: :system}
  end

  def user(content) when is_binary(content) do
    %__MODULE__{role: :user, content: clean_white_space(content)}
  end

  def user(%__MODULE__{} = msg) do
    %__MODULE__{msg | role: :user}
  end

  def model(content) when is_binary(content) do
    %__MODULE__{role: :model, content: clean_white_space(content)}
  end

  def model(tool_calls) when is_list(tool_calls) do
    %__MODULE__{role: :model, tool_calls: tool_calls}
  end

  def model(%__MODULE__{} = msg) do
    %__MODULE__{msg | role: :model}
  end

  def model(content, tool_calls) when is_binary(content) and is_list(tool_calls) do
    %__MODULE__{role: :model, content: clean_white_space(content), tool_calls: tool_calls}
  end

  def tool_result(tool_name, tool_response) do
    %__MODULE__{role: :user, tool_results: [%{name: tool_name, response: tool_response}]}
  end

  def tool_results(tool_results) when is_list(tool_results) do
    %__MODULE__{role: :user, tool_results: tool_results}
  end

  def content_with_tool_result(content, tool_name, tool_response) when is_binary(content) do
    %__MODULE__{
      role: :user,
      content: clean_white_space(content),
      tool_results: [%{name: tool_name, response: tool_response}]
    }
  end

  def content_with_tool_results(content, tool_results)
      when is_binary(content) and is_list(tool_results) do
    %__MODULE__{
      role: :user,
      content: clean_white_space(content),
      tool_results: tool_results
    }
  end

  def maybe_user(content) when is_binary(content) do
    %__MODULE__{role: :user, content: clean_white_space(content)}
  end

  def maybe_user(%__MODULE__{} = msg) do
    %__MODULE__{msg | role: :user}
  end

  def maybe_user(nil), do: nil

  def maybe_concat(messages, nil) do
    messages
  end

  def maybe_concat(messages, %__MODULE__{} = msg) when is_list(messages) do
    messages ++ [msg]
  end

  def maybe_concat(messages, new_messages) when is_list(messages) and is_list(new_messages) do
    messages ++ new_messages
  end

  def clean_white_space(text) do
    text
    |> String.replace(~r/\n{2,}/, "\n\n")
    |> String.trim()
  end
end
