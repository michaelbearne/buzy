defmodule Buzy.Llm.Clients.Helpers do
  require Logger
  import Buzy.Llm.Helpers, only: [trigger_callback: 3]

  alias Buzy.Generators, as: Gen

  alias Buzy.Llm.Error
  alias Buzy.Llm.Clients.Parms
  alias Buzy.Llm.Response

  @doc """
  Creates and returns an anonymous function to handle the streaming response
  from an API.

  Accepts the following functions that handle the API-specific requirements:

  - `decode_stream_fn` - a function that parses the raw results from an API. It
    deals with the specifics or oddities of a data source. The results come back
    as `{[list_of_parsed_json_maps], "incomplete text to buffer"}`. In some
    cases, a API may span the JSON data response across messages. This function
    assembles what is complete and returns any incomplete portion that is passed
    in on the next iteration of the function.

  - `transform_data_fn` - a function that is executed to process the parsed
    JSON data in the form of an Elixir map into a LangChain struct of the
    appropriate type.

  - `callback_fn` - a function that receives a successful result of from the
    `transform_data_fn`.
  """
  @spec handle_stream_fn(
          %{optional(:stream) => boolean()},
          decode_stream_fn :: function(),
          transform_data_fn :: function()
        ) :: function()
  def handle_stream_fn(%Parms{} = parms, decode_stream_fn, transform_data_fn) do
    %{callbacks: callbacks, plugins: plugins, private: private} = parms

    fn
      {:data, raw_data}, {req, %Req.Response{status: 200} = response} ->
        # Fetch any previously incomplete messages that are buffered in the
        # response struct and pass that in with the data for decode.
        buffered = Req.Response.get_private(response, :buffered, "")

        body =
          if response.body == "" do
            %Response{
              id: Gen.id(),
              context: parms.context,
              model: parms.model,
              usage: %Response.Usage{},
              private: private
            }
          else
            response.body
          end

        # write any incomplete portion to the response's private data for when
        # more data is received.
        updated_response =
          case decode_stream_fn.({raw_data, buffered}) do
            {nil, incomplete} ->
              Req.Response.put_private(response, :buffered, incomplete)

            {parsed_chunk, incomplete} ->
              chunked_response = transform_data_fn.(parsed_chunk)

              new_body = handle_chunked_response(body, chunked_response)

              new_private =
                if is_struct(chunked_response, Response.Chunk) do
                  chunked_response =
                    Response.Chunk.parse(chunked_response, new_body.id, parms.context)

                  trigger_callback(callbacks, :on_llm_new_token, chunked_response)
                  trigger_plugins(plugins, new_body.private, chunked_response)
                end

              new_body = %{new_body | private: new_private}

              %{response | body: new_body}
              |> Req.Response.put_private(:buffered, incomplete)
          end

        {:cont, {req, updated_response}}

      {:data, _raw_data}, {req, %Req.Response{status: 401} = _response} ->
        Logger.error("Check API key settings. Request rejected for authentication failure.")
        {:halt, {req, %Error{message: "Authentication failure with request"}}}

      {:data, raw_data}, {req, %Req.Response{status: status} = response}
      when status in 400..599 ->
        case JSON.decode(raw_data) do
          {:ok, data} ->
            {:halt, {req, %{response | body: transform_data_fn.(data)}}}

          {:error, reason} ->
            Logger.error("Failed to JSON decode error response. ERROR: #{inspect(reason)}")
            {:halt, {req, %Error{message: "Failed to handle error response from server."}}}
        end

      {:data, _raw_data}, {req, response} ->
        Logger.error("Unhandled API response!")
        {:halt, {req, response}}
    end
  end

  defp handle_chunked_response(
         %Response{usage: streamed_usage, choices: streamed_choices} = body,
         %Response.Chunk{choices: choices, usage: usage}
       ) do
    %{
      body
      | choices: Response.Choice.merge(streamed_choices, choices),
        usage: Response.Usage.merge(streamed_usage, usage)
    }
  end

  defp handle_chunked_response(_body, %Error{} = error) do
    error
  end

  defp trigger_plugins([], private, _chunked_response) do
    private
  end

  defp trigger_plugins(plugins, private, chunked_response) do
    Enum.reduce(plugins, private, fn plugin, acc ->
      Code.ensure_loaded(plugin)

      if function_exported?(plugin, :on_llm_token, 2) do
        apply(plugin, :on_llm_token, [chunked_response, acc])
      else
        acc
      end
    end)
  end
end
