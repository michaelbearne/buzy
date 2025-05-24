defmodule Buzy do
  @moduledoc """
  Documentation for `Buzy`.
  """

  alias Buzy.Runner.Registration.LocalRegistry

  def start_and_subscribe_to_agent(runner, thread_id, opts \\ [])
      when is_atom(runner) and is_binary(thread_id) and is_list(opts) do
    with {:ok, subscriber_pid} <-
           LocalRegistry.register_subscriber(
             runner,
             thread_id
           ),
         {:ok, _runner_pid} <-
           LocalRegistry.start_runner(
             runner,
             thread_id,
             Keyword.put(opts, :subscribers, subscriber_pid)
           ) do
      {:ok, LocalRegistry.runner_via_tuple(thread_id)}
    else
      {:error, {:already_registered, _pid}} ->
        {:error, {:already_registered, LocalRegistry.runner_via_tuple(thread_id)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
