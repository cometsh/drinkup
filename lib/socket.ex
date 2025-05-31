defmodule Drinkup.Socket do
  @moduledoc """
  gen_statem process for managing the websocket connection to an ATProto relay.
  """

  require Logger
  alias Drinkup.{Event, Options}

  @behaviour :gen_statem
  @timeout :timer.seconds(5)
  # TODO: `flow` determines messages in buffer. Determine ideal value?
  @flow 10

  @op_regular 1
  @op_error -1

  defstruct [:options, :seq, :conn, :stream]

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts, []]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(%Options{} = options, statem_opts) do
    :gen_statem.start_link(__MODULE__, options, statem_opts)
  end

  @impl true
  def init(%{cursor: seq} = options) do
    data = %__MODULE__{seq: seq, options: options}
    {:ok, :disconnected, data, [{:next_event, :internal, :connect}]}
  end

  def disconnected(:enter, _from, data) do
    Logger.debug("Initial connection")
    # TODO: differentiate between initial & reconnects, probably stuff to do with seq
    {:next_state, :disconnected, data}
  end

  def disconnected(:internal, :connect, data) do
    {:next_state, :connecting_http, data}
  end

  def connecting_http(:enter, _from, %{options: options} = data) do
    Logger.debug("Connecting to http")

    %{host: host, port: port} = URI.new!(options.host)

    {:ok, conn} =
      :gun.open(:binary.bin_to_list(host), port, %{
        retry: 0,
        protocols: [:http],
        connect_timeout: @timeout,
        domain_lookup_timeout: @timeout,
        tls_handshake_timeout: @timeout,
        tls_opts: [
          verify: :verify_peer,
          cacerts: :certifi.cacerts(),
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      })

    {:keep_state, %{data | conn: conn}, [{:state_timeout, @timeout, :connect_timeout}]}
  end

  def connecting_http(:info, {:gun_up, _conn, :http}, data) do
    {:next_state, :connecting_ws, data}
  end

  def connecting_http(:state_timeout, :connect_timeout, _data) do
    {:stop, :connect_http_timeout}
  end

  def connecting_ws(:enter, _from, %{conn: conn, seq: seq} = data) do
    Logger.debug("Upgrading connection to websocket")
    path = "/xrpc/com.atproto.sync.subscribeRepos?" <> URI.encode_query(%{cursor: seq})
    stream = :gun.ws_upgrade(conn, path, [], %{flow: @flow})
    {:keep_state, %{data | stream: stream}, [{:state_timeout, @timeout, :upgrade_timeout}]}
  end

  def connecting_ws(:info, {:gun_upgrade, _conn, _stream, ["websocket"], _headers}, data) do
    {:next_state, :connected, data}
  end

  def connecting_ws(:state_timeout, :upgrade_timeout, _data) do
    {:stop, :connect_ws_timeout}
  end

  def connected(:enter, _from, _data) do
    Logger.debug("Connected to websocket")
    :keep_state_and_data
  end

  def connected(:info, {:gun_ws, conn, stream, {:binary, frame}}, %{options: options} = data) do
    # TODO: let clients specify a handler for raw* (*decoded) packets to support any atproto subscription
    # Will also need support for JSON frames
    with {:ok, header, next} <- CAR.DagCbor.decode(frame),
         {:ok, payload, _} <- CAR.DagCbor.decode(next),
         {%{"op" => @op_regular, "t" => type}, _} <- {header, payload},
         true <- Event.valid_seq?(data.seq, payload["seq"]) do
      data = %{data | seq: payload["seq"] || data.seq}
      message = Event.from(type, payload)
      :ok = :gun.update_flow(conn, stream, @flow)

      case message do
        nil ->
          Logger.warning("Received unrecognised event from firehose: #{inspect({type, payload})}")

        message ->
          Event.dispatch(message, options)
      end

      {:keep_state, data}
    else
      false ->
        Logger.error("Got out of sequence or invalid `seq` from Firehose")
        {:keep_state, data}

      {%{"op" => @op_error, "t" => type}, payload} ->
        Logger.error("Got error from Firehose: #{inspect({type, payload})}")
        {:keep_state, data}

      {:error, reason} ->
        Logger.warning("Failed to decode frame from Firehose: #{inspect(reason)}")
        {:keep_state, data}
    end
  end

  def connected(:info, {:gun_ws, _conn, _stream, :close}, _data) do
    Logger.info("Websocket closed, reason unknown")
    {:keep_state_and_data, [{:next_event, :internal, :reconnect}]}
  end

  def connected(:info, {:gun_ws, _conn, _stream, {:close, errno, reason}}, _data) do
    Logger.info("Websocket closed, errno: #{errno}, reason: #{inspect(reason)}")
    {:keep_state_and_data, [{:next_event, :internal, :reconnect}]}
  end

  def connected(:info, {:gun_down, old_conn, _proto, _reason, _killed_streams}, %{conn: new_conn})
      when old_conn != new_conn do
    Logger.debug("Ignoring received :gun_down for a previous connection.")
    :keep_state_and_data
  end

  def connected(:info, {:gun_down, _conn, _proto, _reason, _killed_streams}, _data) do
    Logger.info("Websocket connection killed. Attempting to reconnect")
    {:keep_state_and_data, [{:next_event, :internal, :reconnect}]}
  end

  def connected(:internal, :reconnect, %{conn: conn} = data) do
    :ok = :gun.close(conn)
    :ok = :gun.flush(conn)

    # TODO: reconnect backoff
    {:next_state, :disconnected, %{data | conn: nil, stream: nil},
     [{:next_event, :internal, :connect}]}
  end
end
