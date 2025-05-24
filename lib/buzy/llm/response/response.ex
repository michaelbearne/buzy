defmodule Buzy.Llm.Response do
  alias Buzy.Generators, as: Gen

  alias Buzy.Llm.Message
  alias Buzy.Llm.Clients.StructuredFormat
  alias Buzy.Llm.Response.Choice
  alias Buzy.Llm.Response.ToolCall

  @type t :: %__MODULE__{
          # validation_errors: [Phase.Error.t()],
          # result: nil | Result.Object.t(),
          # Llm: Llm.t(),
          # private: %{},
          # halted: halted
        }

  defstruct [
    :id,
    :choices,
    :context,
    :usage,
    :model,
    :tool_calls,
    :structured_output,
    :model_message,
    :valid,
    :has_model_message,
    :has_tool_calls,
    :has_structured_output,
    :private
  ]

  def pluck_message_content(responses) when is_list(responses) do
    responses |> Enum.map(&pluck_message_content/1) |> List.flatten()
  end

  def pluck_message_content(%__MODULE__{choices: choices}) do
    Enum.map(choices, fn %{"message" => %{"content" => content}} ->
      content
    end)
  end

  def as_string(%__MODULE__{choices: choices}) do
    Enum.map(choices, fn %{parts: [%__MODULE__.Part{type: :text, content: content}]} ->
      content
    end)
  end

  def parse(
        %__MODULE__{id: id, context: context, choices: choices} = resp,
        llm,
        %StructuredFormat{} = structured_fmt
      ) do
    parsed = Enum.map(choices, &Choice.parse(&1, llm, structured_fmt))
    structured_output = first_parsed_content(parsed)
    tool_calls = Choice.tool_calls(choices)
    model_message = maybe_to_message(parsed)
    errors = errors(%{resp | choices: parsed})

    %{
      resp
      | id: id || Gen.id(),
        choices: parsed,
        context: context || llm.context,
        valid: Enum.empty?(errors),
        model_message: model_message,
        structured_output: structured_output,
        tool_calls: tool_calls,
        has_model_message: !is_nil(model_message),
        has_structured_output: !is_nil(structured_output),
        has_tool_calls: !is_nil(tool_calls) && !Enum.empty?(tool_calls)
    }
  end

  def errors(%__MODULE__{choices: choices}) do
    choices |> Enum.map(&Choice.errors/1) |> List.flatten()
  end

  def parsed_content(%__MODULE__{choices: choices}) do
    choices |> Enum.map(&Choice.parsed_content/1)
  end

  def first_parsed_content(%__MODULE__{choices: choices}) do
    first_parsed_content(choices)
  end

  def first_parsed_content(choices) when is_list(choices) do
    Enum.find_value(choices, &Choice.first_parsed_content/1)
  end

  def first_content(%__MODULE__{choices: choices}) do
    Choice.first_content(choices)
  end

  defp maybe_to_message(choices) when is_list(choices) do
    tool_calls = Choice.tool_calls(choices)
    content = Choice.first_content(choices)

    case {content, tool_calls} do
      {content, []} when is_binary(content) ->
        Message.model(content)

      {nil, [%ToolCall{} | _rest] = tool_calls} ->
        Message.model(tool_calls)

      {content, [%ToolCall{} | _rest] = tool_calls} when is_binary(content) ->
        Message.model(content, tool_calls)

      _ ->
        nil
    end
  end
end
