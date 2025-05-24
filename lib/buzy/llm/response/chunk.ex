defmodule Buzy.Llm.Response.Chunk do
  alias Buzy.Llm.Response.Choice

  @type t :: %__MODULE__{
          # validation_errors: [Phase.Error.t()],
          # result: nil | Result.Object.t(),
          # Llm: Llm.t(),
          # private: %{},
          # halted: halted
        }

  defstruct [
    :response_id,
    :choices,
    :context,
    :usage,
    :model,
    :content,
    # :private,
    :tool_call,
    :finish_reason,
    :valid
  ]

  def finished?(%__MODULE__{choices: choices}) do
    Choice.finished?(choices)
  end

  def parse(%__MODULE__{choices: choices, context: context} = chunk, response_id, parms_context) do
    content = Choice.first_content(choices)
    tool_call = Choice.first_tool_call(choices)
    finish_reason = Choice.first_finish_reason(choices)

    if content || tool_call do
      %__MODULE__{
        chunk
        | response_id: response_id,
          context: context || parms_context,
          content: content,
          tool_call: tool_call,
          finish_reason: finish_reason,
          valid: true
      }
    else
      chunk
    end
  end
end
