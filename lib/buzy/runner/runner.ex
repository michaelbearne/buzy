defmodule Buzy.Runner do
  use GenServer, restart: :temporary
  require Logger

  alias Buzy.Runner
  alias Buzy.Runner.Graph

  defmacro __using__(using_opts) do
    quote location: :keep do
      def start_link(opts \\ []) do
        opts = Keyword.merge(unquote(using_opts), opts)
        Runner.start_link(__MODULE__, opts)
      end

      @doc """
      Provides a child specification to allow the event handler to be easily
      supervised.

      Supports the same options as `start_link/3`.

      The default options supported by `GenServer.start_link/3` are also
      supported, including the `:hibernate_after` option which allows the
      runner to go into hibernation after a period of inactivity.

      ### Example

          Supervisor.start_link([
            {ExampleHandler, []}
          ], strategy: :one_for_one)

      """
      def child_spec(opts) do
        opts = Keyword.merge(unquote(using_opts), opts)

        spec =
          case Keyword.get(opts, :concurrency, 1) do
            1 ->
              %{
                id: {__MODULE__, opts},
                start: {__MODULE__, :start_link, [opts]},
                restart: :permanent,
                type: :worker
              }

            concurrency when is_integer(concurrency) and concurrency > 1 ->
              opts = Keyword.put(opts, :module, __MODULE__)

              Runner.Supervisor.child_spec(opts)

            invalid ->
              raise ArgumentError,
                    "invalid `:concurrency` for event handler, expected a positive integer but got: " <>
                      inspect(invalid)
          end

        Supervisor.child_spec(spec, [])
      end

      def invoke(pid, runner_state \\ nil) do
        Runner.invoke(pid, runner_state)
      end

      def call(pid, runner_state \\ nil, opts \\ []) do
        Runner.call(pid, runner_state, opts)
      end

      def get_state(pid) do
        Runner.get_runner_state(pid)
      end

      def get_state(pid, fun) when is_function(fun, 1) do
        Runner.get_runner_state(pid, fun)
      end

      def get_current_node(pid) do
        Runner.get_current_node(pid)
      end
    end
  end

  defstruct [
    :opts,
    :runner_module,
    :runner_graph,
    :runner_state,
    :current_node,
    :subscribers,
    :reply_ref,
    :output_fn,
    :checkpointer
  ]

  def start_link(runner_module, opts \\ []) do
    {start_opts, runner_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    callers = get_callers(self())

    state = %__MODULE__{
      runner_module: runner_module,
      opts: runner_opts,
      subscribers: if(opts[:subscribers], do: List.wrap(opts[:subscribers]), else: []),
      checkpointer: opts[:checkpointer]
    }

    GenServer.start_link(__MODULE__, {state, callers}, start_opts)
  end

  @doc false
  @impl GenServer
  def init({%__MODULE__{} = state, callers}) do
    put_callers(callers)
    Process.flag(:trap_exit, true)
    {:ok, state, {:continue, :setup}}
  end

  def invoke(pid, input_state \\ nil) do
    GenServer.cast(pid, {:invoke, input_state})
  end

  @two_min 2 * 60 * 1000
  def call(pid, input_state \\ nil, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @two_min)
    output_fn = Keyword.get(opts, :output_fn)
    GenServer.call(pid, {:invoke, input_state, output_fn}, timeout)
  end

  def get_runner_state(pid) do
    GenServer.call(pid, :get_runner_state)
  end

  def get_runner_state(pid, fun) do
    GenServer.call(pid, {:get_runner_state, fun})
  end

  def get_current_node(pid) do
    GenServer.call(pid, :get_current_node)
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.debug(inspect(state) <> " is shutting down due to #{inspect(reason)}")
  end

  @doc false
  @impl GenServer
  def handle_continue(:setup, %__MODULE__{} = state) do
    %{runner_module: runner_module, opts: _opts} = state
    # todo check is a fun/1 and pass ops if there
    runner_graph = runner_module.graph()

    checkpointer_state =
      if state.checkpointer[:init] && is_function(state.checkpointer[:init], 0) do
        state.checkpointer[:init].()
      else
        %{}
      end

    runner_state = Map.merge(runner_module.init_state(), checkpointer_state[:runner_state] || %{})

    state = %{
      state
      | runner_graph: runner_graph,
        runner_state: runner_state,
        current_node: checkpointer_state[:current_node]
    }

    {:noreply, state}
  end

  def handle_continue(:next_node, %__MODULE__{} = state) do
    %{runner_graph: graph, current_node: current_node} = state
    next_node = Graph.next_node(graph, current_node)
    handle_next_node(next_node, state)
  end

  def handle_continue(:invoke_node, %__MODULE__{} = state) do
    %{
      runner_module: module,
      runner_graph: graph,
      current_node: active_node,
      runner_state: runner_state,
      subscribers: subscribers,
      opts: opts
    } = state

    active_node_fn = Graph.get_node_fn(graph, active_node)

    if !active_node_fn do
      raise "The graph node #{inspect(active_node)} is not configured, node function not found!"
    end

    node_runner_state =
      invoke_active_node(active_node_fn, active_node, runner_state, subscribers, opts)

    new_runner_state = merge_runner_state(module, runner_state, node_runner_state)
    new_state = %{state | runner_state: new_runner_state}
    {:noreply, new_state, {:continue, :next_node}}
  end

  @impl GenServer
  def handle_call({:invoke, runner_state, output_fn}, from, %__MODULE__{} = state) do
    %{
      runner_module: module,
      runner_state: existing_runner_state
    } = state

    new_runner_state = merge_runner_state(module, existing_runner_state, runner_state)

    new_state = %{
      state
      | runner_state: new_runner_state,
        reply_ref: from,
        output_fn: output_fn
    }

    {:noreply, new_state, {:continue, :next_node}}
  end

  def handle_call(:get_runner_state, _from, %__MODULE__{runner_state: runner_state} = state) do
    {:reply, runner_state, state}
  end

  def handle_call({:get_runner_state, fun}, _from, %__MODULE__{} = state) do
    %{runner_state: runner_state} = state
    {:reply, fun.(runner_state), state}
  end

  def handle_call(:get_current_node, _from, %__MODULE__{} = state) do
    %{current_node: current_node} = state
    {:reply, current_node, state}
  end

  @impl GenServer
  def handle_cast({:invoke, runner_state}, %__MODULE__{} = state) do
    %{
      runner_module: module,
      runner_state: existing_runner_state
    } = state

    new_runner_state = merge_runner_state(module, existing_runner_state, runner_state)
    new_state = %{state | runner_state: new_runner_state}
    {:noreply, new_state, {:continue, :next_node}}
  end

  defp handle_next_node(next_node, state) do
    %{runner_state: runner_state, opts: opts, reply_ref: reply_ref} = state

    case next_node do
      :end ->
        # exit as graph compleated
        if reply_ref, do: GenServer.reply(reply_ref, runner_state)
        {:stop, :normal, %{state | current_node: nil, reply_ref: nil}}

      nil ->
        # wait on inactivity timeout to exit
        if reply_ref, do: GenServer.reply(reply_ref, runner_state)
        new_state = %{state | reply_ref: nil}
        {:noreply, new_state}

      next_node when is_atom(next_node) ->
        new_state = %{state | current_node: next_node}
        {:noreply, new_state, {:continue, :invoke_node}}

      conditional_edge when is_function(conditional_edge, 1) ->
        next_node = conditional_edge.(runner_state)
        handle_next_node(next_node, state)

      conditional_edge when is_function(conditional_edge, 2) ->
        next_node = conditional_edge.(runner_state, opts)
        handle_next_node(next_node, state)
    end
  end

  defp merge_runner_state(runner_module, existing, new) when is_map(existing) and is_map(new) do
    if function_exported?(runner_module, :reducers, 0) do
      reducers = runner_module.reducers()

      Map.merge(existing, new, fn k, v1, v2 ->
        reducer = reducers[k]
        if reducer, do: reducer.(v1, v2), else: v2
      end)
    else
      Map.merge(existing, new, fn _k, _v1, v2 -> v2 end)
    end
  end

  defp invoke_active_node(active_node_fn, _active_node_name, runner_state, _subscribers, _opts)
       when is_function(active_node_fn, 1) do
    active_node_fn.(runner_state)
  end

  defp invoke_active_node(active_node_fn, active_node_name, runner_state, subscribers, opts)
       when is_function(active_node_fn, 2) do
    callbacks =
      for subscriber <- subscribers do
        [on_llm_end: subscriber, on_llm_new_token: subscriber]
      end
      |> List.flatten()

    opts =
      Keyword.merge(opts, [callbacks: callbacks, context: %{active_node: active_node_name}], fn
        :active_node, v1, v2 -> Map.merge(v1, v2)
        :callbacks, v1, v2 -> v1 ++ v2
      end)

    active_node_fn.(runner_state, opts)
  end

  defp get_callers(owner) do
    case :erlang.get(:"$callers") do
      [_ | _] = list -> [owner | list]
      _ -> [owner]
    end
  end

  defp put_callers(callers) do
    Process.put(:"$callers", callers)
  end
end
