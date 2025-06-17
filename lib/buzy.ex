defmodule Buzy do
  @external_resource readme = Path.join([__DIR__, "../README.md"])
  @doc_readme File.read!(readme)

  @moduledoc """
  #{@doc_readme}
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
             Keyword.merge(opts, subscribers: subscriber_pid, thread_id: thread_id)
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
