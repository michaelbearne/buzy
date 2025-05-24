defmodule Buzy.Runner.Supervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link(opts) do
    {start_opts, supervisor_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    start_opts = Keyword.put_new(start_opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, supervisor_opts, start_opts)
  end

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
