defmodule Buzy.Llm.Execution do
  alias Buzy.Llm
  alias Buzy.Llm.{Response, Error}
  alias Buzy.Llm.Error

  @type halted() :: boolean()
  @type private :: %{optional(atom) => any}

  @type t :: %__MODULE__{
          llm: Llm.t(),
          response: Response.t() | Error.t() | nil,
          private: private
          # halted: halted
        }

  defstruct [
    :llm,
    :messages,
    response: nil,
    private: %{}
    # halted: false
  ]

  @doc """
  Assigns a new **private** key and value in the execution
  This storage is meant to be used by plugins

  """
  @spec put_private(t, atom, term) :: t
  def put_private(%__MODULE__{private: private} = exec, key, value) when is_atom(key) do
    %{exec | private: Map.put(private, key, value)}
  end

  @spec delete_private(t, atom) :: t
  def delete_private(%__MODULE__{private: private} = exec, key) when is_atom(key) do
    %{exec | private: Map.delete(private, key)}
  end

  @doc """
  Assigns multiple **private** keys and values in the execution.
  """
  @spec merge_private(t, Enumerable.t()) :: t
  def merge_private(%__MODULE__{private: private} = exec, new) do
    %{exec | private: Enum.into(new, private)}
  end

  def put_response(%__MODULE__{} = exec, %Response{} = response) do
    %{exec | response: response}
  end
end
