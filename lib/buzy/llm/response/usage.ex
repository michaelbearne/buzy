defmodule Buzy.Llm.Response.Usage do
  # @derive Jason.Encoder
  defstruct completion_tokens: 0, prompt_tokens: 0, total_tokens: 0

  def merge(%__MODULE__{} = l, %__MODULE__{} = r) do
    %__MODULE__{
      completion_tokens: l.completion_tokens + r.completion_tokens,
      prompt_tokens: l.prompt_tokens + r.prompt_tokens,
      total_tokens: l.total_tokens + r.total_tokens
    }
  end
end
