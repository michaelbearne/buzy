defmodule Buzy.Runner.Graph do
  defstruct parallel: true,
            nodes: [],
            edges: []

  # error_edges

  def new(), do: %__MODULE__{}

  def parallel(%__MODULE__{} = graph, parallel) do
    %{graph | parallel: parallel}
  end

  def add_node(%__MODULE__{nodes: nodes} = graph, node, fun) do
    %{graph | nodes: [{node, fun} | nodes]}
  end

  def add_edge(%__MODULE__{edges: edges} = graph, start_key, end_key) do
    %{graph | edges: [{start_key, end_key} | edges]}
  end

  def add_conditional_edges(
        %__MODULE__{edges: edges} = graph,
        start_key,
        routing_fun,
        _routing_fun_map \\ nil
      )
      when is_function(routing_fun, 1) do
    %{graph | edges: [{start_key, routing_fun} | edges]}
  end

  def next_node(%__MODULE__{edges: edges}, nil) do
    Enum.find_value(edges, fn
      {:start, end_key} -> end_key
      _ -> nil
    end)
  end

  def next_node(%__MODULE__{edges: edges}, current_node) when is_atom(current_node) do
    Enum.find_value(edges, fn
      {^current_node, end_key} -> end_key
      _ -> nil
    end)
  end

  def get_node_fn(%__MODULE__{nodes: nodes}, node_key) do
    Enum.find_value(nodes, fn
      {^node_key, node_fn} -> node_fn
      _ -> nil
    end)
  end
end
