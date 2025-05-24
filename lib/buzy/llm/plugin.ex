defmodule Buzy.Llm.Plugin do
  @type t :: module

  alias Buzy.Llm.Execution
  alias Buzy.Llm.Response.Chunk

  @doc """
  NOTE: These functions are given the full private accumulator.
  Namespacing is suggested to avoid conflicts.
  """
  @callback before_call(execution :: Execution.t()) :: Execution.t()

  @callback after_call(execution :: Execution.t()) :: Execution.t()

  @callback on_llm_token(chunk :: Chunk.t(), private :: Execution.private()) ::
              Execution.private()

  @optional_callbacks before_call: 1, after_call: 1, on_llm_token: 2
end
