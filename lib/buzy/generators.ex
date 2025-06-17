defmodule Buzy.Generators do
  Code.ensure_loaded?(Ecto.ULID)
  Code.ensure_loaded?(UUID)

  cond do
    function_exported?(Ecto.ULID, :generate, 0) ->
      def id, do: Ecto.ULID.generate()

    function_exported?(UUID, :uuid4, 0) ->
      def id, do: UUID.uuid4()

    true ->
      raise("No id generator found please add :ecto_ulid or :elixir_uuid to your deps")
  end

  def now, do: DateTime.utc_now()
end
