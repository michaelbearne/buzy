defmodule Buzy.Llm.Helpers do
  def trigger_callback(callbacks, event, result) do
    for {^event, cb} <- callbacks, do: do_trigger_callback(cb, event, result)
  end

  defp do_trigger_callback(cb, _event, result) when is_function(cb, 1) do
    cb.(result)
  end

  defp do_trigger_callback(pid, event, result) when is_pid(pid) do
    send(pid, {event, result})
  end

  defp do_trigger_callback({:via, Registry, {registry_mod, key}}, event, result) do
    Registry.dispatch(registry_mod, key, fn entries ->
      for {pid, _} <- entries, do: send(pid, {event, result})
    end)
  end

  def maybe_broadcast_to_subscribers(pid, msg) when is_pid(pid) do
    send(pid, msg)
  end

  def maybe_broadcast_to_subscribers({:via, Registry, {registry_mod, key}}, msg) do
    Registry.dispatch(registry_mod, key, fn entries ->
      for {pid, _} <- entries, do: send(pid, msg)
    end)
  end

  def maybe_broadcast_to_subscribers(nil, _msg), do: nil
end
