defmodule Buzy.Llm.Plugins.SimpleCache do
  @behaviour Buzy.Llm.Plugin
  import Buzy.Llm.Helpers, only: [trigger_callback: 3]

  alias Buzy.Llm.{Execution, Response}

  @table_name :llm_requests_cache

  def before_call(%Execution{llm: llm, messages: messages} = exec) do
    open_cache()

    # not sure why the order of the map can be different when just compiled so forcing the order
    # todo still not a 100% this works after a restart
    hash_key =
      Murmur.hash_x64_128([
        llm |> Map.from_struct() |> Map.drop([:context, :plugins, :callbacks]) |> Enum.sort(),
        Enum.map(messages, &(&1 |> Map.from_struct() |> Enum.sort())) |> Enum.sort()
      ])

    case Pockets.get(@table_name, hash_key) do
      %{response: resp, chunks: chunks} ->
        for chunk <- chunks do
          Process.sleep(20)
          trigger_callback(llm.callbacks, :on_llm_new_token, %{chunk | context: llm.context})
        end

        %{
          exec
          | response: %{
              resp
              | context: llm.context,
                private: %{cache: %{hash_key: hash_key, hit: true}}
            }
        }

      %Response{} = resp ->
        %{
          exec
          | response: %{
              resp
              | context: llm.context,
                private: %{cache: %{hash_key: hash_key, hit: true}}
            }
        }

      nil ->
        Execution.put_private(exec, :cache, %{hash_key: hash_key})
    end
  end

  def after_call(%{private: %{cache: %{hit: true}}} = exec) do
    exec
  end

  def after_call(%{private: %{cache: %{hash_key: hash_key, chunks: chunks}}} = exec)
      when is_list(chunks) do
    open_cache()

    response = %{exec.response | context: nil, private: nil}
    Pockets.put(@table_name, hash_key, %{response: response, chunks: Enum.reverse(chunks)})
    Execution.delete_private(exec, :cache)
  end

  def after_call(%{private: %{cache: %{hash_key: hash_key}}} = exec) do
    open_cache()
    response = %{exec.response | context: nil, private: nil}
    Pockets.put(@table_name, hash_key, response)
    Execution.delete_private(exec, :cache)
  end

  def on_llm_token(chunk, private) do
    cache =
      Map.update(private.cache, :chunks, [chunk], fn chunks ->
        [%{chunk | context: nil} | chunks]
      end)

    Map.put(private, :cache, cache)
  end

  defp open_cache(_opts \\ []) do
    cache_path = Path.relative_to_cwd(".buzy/#{@table_name}.dets")
    {:ok, @table_name} = Pockets.open(@table_name, cache_path, create?: true)
  end

  def close_cache(_opts \\ []) do
    Pockets.close(@table_name)
  end
end
