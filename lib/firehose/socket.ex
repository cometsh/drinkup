defmodule Drinkup.Firehose.Socket do
  @moduledoc """
  WebSocket connection handler for ATProto relay subscriptions.

  Implements the Drinkup.Socket behaviour to manage connections to an ATProto
  Firehose relay, handling CAR/CBOR-encoded frames and dispatching events to
  the configured consumer.
  """

  use Drinkup.Socket

  require Logger
  alias Drinkup.Firehose.{Event, Options}

  @op_regular 1
  @op_error -1

  @impl true
  def init(opts) do
    options = Keyword.fetch!(opts, :options)
    {:ok, %{seq: options.cursor, options: options, host: options.host}}
  end

  def start_link(%Options{} = options, statem_opts) do
    # Build opts for Drinkup.Socket from Options struct
    socket_opts = [
      host: options.host,
      cursor: options.cursor,
      options: options
    ]

    Drinkup.Socket.start_link(__MODULE__, socket_opts, statem_opts)
  end

  @impl true
  def build_path(%{seq: seq}) do
    cursor_param = if seq, do: %{cursor: seq}, else: %{}
    "/xrpc/com.atproto.sync.subscribeRepos?" <> URI.encode_query(cursor_param)
  end

  @impl true
  def handle_frame({:binary, frame}, {%{seq: seq, options: options} = data, _conn, _stream}) do
    with {:ok, header, next} <- CAR.DagCbor.decode(frame),
         {:ok, payload, _} <- CAR.DagCbor.decode(next),
         {%{"op" => @op_regular, "t" => type}, _} <- {header, payload},
         true <- Event.valid_seq?(seq, payload["seq"]) do
      new_seq = payload["seq"] || seq

      case Event.from(type, payload) do
        nil ->
          Logger.warning("Received unrecognised event from firehose: #{inspect({type, payload})}")

        message ->
          Event.dispatch(message, options)
      end

      {:ok, %{data | seq: new_seq}}
    else
      false ->
        Logger.error("Got out of sequence or invalid `seq` from Firehose")
        :noop

      {%{"op" => @op_error, "t" => type}, payload} ->
        Logger.error("Got error from Firehose: #{inspect({type, payload})}")
        :noop

      {:error, reason} ->
        Logger.warning("Failed to decode frame from Firehose: #{inspect(reason)}")
        :noop
    end
  end

  @impl true
  def handle_frame(:close, _data) do
    Logger.info("Websocket closed, reason unknown")
    nil
  end

  @impl true
  def handle_frame({:close, errno, reason}, _data) do
    Logger.info("Websocket closed, errno: #{errno}, reason: #{inspect(reason)}")
    nil
  end

  @impl true
  def handle_frame({:text, _text}, _data) do
    Logger.warning("Received unexpected text frame from Firehose")
    :noop
  end
end
