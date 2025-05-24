defmodule Buzy.Llm.Response.ToolCall do
  defstruct [:args, :name]

  def build(call) do
    %__MODULE__{
      name: call["name"],
      args: call["args"]
    }
  end
end
