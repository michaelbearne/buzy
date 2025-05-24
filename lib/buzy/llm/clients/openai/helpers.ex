defmodule Buzy.Llm.Clients.Openai.Helpers do
  def map_role(:user), do: "user"
  def map_role(:system), do: "system"
  def map_role(:model), do: "assistant"

  def unmap_role("assistant"), do: :model
  def unmap_role("function"), do: :tool

  # https://platform.openai.com/docs/api-reference/chat/object

  # Natural stop point of the model or provided stop sequence.
  def map_finish_reason("stop"), do: :stop
  # if the maximum number of tokens specified in the request was reached,
  def map_finish_reason("length"), do: :length
  # if content was omitted due to a flag from our content filters
  def map_finish_reason("content_filter"), do: :content_filter
  # if the model called a tool
  def map_finish_reason("tool_calls"), do: :tool_calls

  @doc """
  Decode a streamed response from an OpenAI-compatible server. Parses a string
  of received content into an Elixir map data structure using string keys.

  If a partial response was received, meaning the JSON text is split across
  multiple data frames, then the incomplete portion is returned as-is in the
  buffer. The function will be successively called, receiving the incomplete
  buffer data from a previous call, and assembling it to parse.
  """
  @spec decode_stream({String.t(), String.t()}) :: {%{String.t() => any()}}
  def decode_stream({raw_data, _buffer}, _done \\ []) do
    case raw_data do
      <<"[{\n  \"error\":", _rest::binary>> ->
        parse_chunk(raw_data)

      <<"[", chunk::binary>> ->
        parse_chunk(chunk)

      <<",", chunk::binary>> ->
        parse_chunk(chunk)

      <<"]">> ->
        parse_chunk("")

      "" ->
        parse_chunk("")

      chunk ->
        parse_chunk(chunk)
    end
  end

  defp parse_chunk(""), do: {nil, ""}

  defp parse_chunk(chunk) do
    case Jason.decode(chunk) do
      {:ok, parsed} ->
        {parsed, ""}

      {:error, _reason} ->
        {nil, chunk}
    end
  end
end
