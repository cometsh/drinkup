defmodule Drinkup.Jetstream.Socket do
  @moduledoc """
  WebSocket connection handler for Jetstream event streams.

  Implements the Drinkup.Socket behaviour to manage connections to a Jetstream
  service, handling zstd-compressed JSON events and dispatching them to the
  configured consumer.
  """

  use Drinkup.Socket

  require Logger
  alias Drinkup.Jetstream.{Event, Options}

  @dict_path "priv/jetstream/zstd_dictionary"
  @external_resource @dict_path
  @zstd_dict File.read!(@dict_path)

  @impl true
  def init(opts) do
    options = Keyword.fetch!(opts, :options)

    {:ok, %{options: options, host: options.host, cursor: options.cursor}}
  end

  def start_link(%Options{} = options, statem_opts) do
    socket_opts = [
      host: options.host,
      options: options
    ]

    statem_opts =
      Keyword.put(
        statem_opts,
        :name,
        {:via, Registry, {Drinkup.Registry, {options.name, JetstreamSocket}}}
      )

    Drinkup.Socket.start_link(__MODULE__, socket_opts, statem_opts)
  end

  @impl true
  def build_path(%{options: options}) do
    query_params = [compress: "true"]

    query_params =
      query_params
      |> put_collections(options.wanted_collections)
      |> put_dids(options.wanted_dids)
      |> put_cursor(options.cursor)
      |> put_max_size(options.max_message_size_bytes)
      |> put_require_hello(options.require_hello)

    "/subscribe?" <> URI.encode_query(query_params)
  end

  @impl true
  def handle_frame(
        {:binary, compressed_data},
        {%{options: options} = data, _conn, _stream}
      ) do
    case decompress_and_parse(compressed_data) do
      {:ok, payload} ->
        case Event.from(payload) do
          nil ->
            # Event.from already logs warnings for unrecognized events
            :noop

          event ->
            Event.dispatch(event, options)
            # Update cursor with the event's time_us
            new_cursor = Map.get(payload, "time_us")
            {:ok, %{data | cursor: new_cursor}}
        end

      # TODO: sometimes getting ZSTD_CONTENTSIZE_UNKNOWN
      {:error, reason} ->
        Logger.error(
          "[Drinkup.Jetstream.Socket] Failed to decompress/parse frame: #{inspect(reason)}"
        )

        :noop
    end
  end

  @impl true
  def handle_frame({:text, json}, {%{options: options} = data, _conn, _stream}) do
    # Text frames shouldn't happen since we force compression, but handle them anyway
    case Jason.decode(json) do
      {:ok, payload} ->
        case Event.from(payload) do
          nil ->
            :noop

          event ->
            Event.dispatch(event, options)
            new_cursor = Map.get(payload, "time_us")
            {:ok, %{data | cursor: new_cursor}}
        end

      {:error, reason} ->
        Logger.error("[Drinkup.Jetstream.Socket] Failed to decode JSON: #{inspect(reason)}")
        :noop
    end
  end

  @impl true
  def handle_frame(:close, _data) do
    Logger.info("[Drinkup.Jetstream.Socket] WebSocket closed, reason unknown")
    nil
  end

  @impl true
  def handle_frame({:close, errno, reason}, _data) do
    Logger.info(
      "[Drinkup.Jetstream.Socket] WebSocket closed, errno: #{errno}, reason: #{inspect(reason)}"
    )

    nil
  end

  @impl true
  def handle_connected({user_data, conn, stream}) do
    # Register connection for options updates
    Registry.register(
      Drinkup.Registry,
      {user_data.options.name, JetstreamConnection},
      {conn, stream}
    )

    {:ok, user_data}
  end

  @impl true
  def handle_disconnected(_reason, {user_data, _conn, _stream}) do
    # Unregister connection when disconnected
    Registry.unregister(Drinkup.Registry, {user_data.options.name, JetstreamConnection})
    {:ok, user_data}
  end

  # Can't use `create_ddict` as the value of `@zstd_dict` because it returns a reference :(
  @spec get_dictionary() :: reference()
  defp get_dictionary() do
    case :ezstd.create_ddict(@zstd_dict) do
      {:error, reason} ->
        raise ArgumentError,
              "somehow failed to created Jetstream's ZSTD dictionary: #{inspect(reason)}"

      dict ->
        dict
    end
  end

  @spec decompress_and_parse(binary()) :: {:ok, map()} | {:error, term()}
  defp decompress_and_parse(compressed_data) do
    with ctx when is_reference(ctx) <-
           :ezstd.create_decompression_context(byte_size(compressed_data)),
         :ok <- :ezstd.select_ddict(ctx, get_dictionary()),
         iolist when is_list(iolist) <- :ezstd.decompress_streaming(ctx, compressed_data),
         decompressed <- IO.iodata_to_binary(iolist),
         {:ok, payload} <- JSON.decode(decompressed) do
      {:ok, payload}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec put_collections(keyword(), [String.t()]) :: keyword()
  defp put_collections(params, []), do: params

  defp put_collections(params, collections) when is_list(collections) do
    Enum.reduce(collections, params, fn collection, acc ->
      [{:wantedCollections, collection} | acc]
    end)
  end

  @spec put_dids(keyword(), [String.t()]) :: keyword()
  defp put_dids(params, []), do: params

  defp put_dids(params, dids) when is_list(dids) do
    Enum.reduce(dids, params, fn did, acc ->
      [{:wantedDids, did} | acc]
    end)
  end

  @spec put_cursor(keyword(), integer() | nil) :: keyword()
  defp put_cursor(params, nil), do: params

  defp put_cursor(params, cursor) when is_integer(cursor), do: [{:cursor, cursor} | params]

  @spec put_max_size(keyword(), integer() | nil) :: keyword()
  defp put_max_size(params, nil), do: params

  defp put_max_size(params, max_size) when is_integer(max_size),
    do: [{:maxMessageSizeBytes, max_size} | params]

  @spec put_require_hello(keyword(), boolean()) :: keyword()
  defp put_require_hello(params, false), do: params

  defp put_require_hello(params, true), do: [{:requireHello, "true"} | params]
end
