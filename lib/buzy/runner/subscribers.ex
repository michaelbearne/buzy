defmodule Buzy.Runner.Subscribers do
  use GenServer, restart: :temporary

  defstruct [
    :subscribers,
    :buffer
  ]

  def start_link(opts \\ []) do
    state = %__MODULE__{
      subscribers: List.wrap(opts[:subscribers])
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  @doc false
  @impl GenServer
  def init(%__MODULE__{} = state) do
    {:ok, state}
  end
end
