defmodule Buzy.Runner.Registration.LocalRegistry do
  alias Buzy.Runner.Supervisor, as: RunnerSupervisor

  def child_spec(_opts) do
    registry_name = __MODULE__

    %{
      id: registry_name,
      start: {Registry, :start_link, [[keys: :unique, name: registry_name]]}
    }
  end

  def register_subscriber(agent, thread_id) when is_atom(agent) and is_binary(thread_id) do
    with {:ok, _} <- Registry.register(__MODULE__, {:subscriber, thread_id}, agent) do
      {:ok, subscriber_via_tuple(thread_id)}
    end
  end

  def lookup_subscriber(thread_id) do
    Registry.lookup(__MODULE__, {:subscriber, thread_id})
  end

  def start_runner(runner, thread_id, opts)
      when is_atom(runner) and is_binary(thread_id) and is_list(opts) do
    via_name = runner_via_tuple(thread_id)
    child_spec = {runner, Keyword.put(opts, :name, via_name)}

    case DynamicSupervisor.start_child(RunnerSupervisor, child_spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  def start_runner(runner, thread_id) when is_atom(runner) and is_binary(thread_id) do
    via_name = runner_via_tuple(thread_id)
    child_spec = {runner, name: via_name}

    case DynamicSupervisor.start_child(RunnerSupervisor, child_spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  def lookup_runner(thread_id) do
    Registry.lookup(__MODULE__, {:runner, thread_id})
  end

  def subscriber_via_tuple(thread_id) do
    {:via, Registry, {__MODULE__, {:subscriber, thread_id}}}
  end

  def runner_via_tuple(thread_id) do
    {:via, Registry, {__MODULE__, {:runner, thread_id}}}
  end
end
