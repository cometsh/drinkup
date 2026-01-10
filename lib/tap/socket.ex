defmodule Drinkup.Tap.Socket do
  @moduledoc """
  WebSocket connection handler for Tap indexer/backfill service.

  Implements the Drinkup.Socket behaviour to manage connections to a Tap service,
  handling JSON-encoded events and dispatching them to the configured consumer.

  Events are acknowledged after successful processing based on the consumer's
  return value:
  - `:ok`, `{:ok, any()}`, or `nil` → Success, ack sent to Tap
  - `{:error, reason}` → Failure, no ack (Tap will retry after timeout)
  - Exception raised → Failure, no ack (Tap will retry after timeout)
  """

  use Drinkup.Socket

  require Logger
  alias Drinkup.Tap.{Event, Options}

  @impl true
  def init(opts) do
    options = Keyword.fetch!(opts, :options)
    {:ok, %{options: options, host: options.host}}
  end

  def start_link(%Options{} = options, statem_opts) do
    socket_opts = build_socket_opts(options)
    Drinkup.Socket.start_link(__MODULE__, socket_opts, statem_opts)
  end

  @impl true
  def build_path(_data) do
    "/channel"
  end

  @impl true
  def handle_frame({:text, json}, {%{options: options} = data, conn, stream}) do
    case Jason.decode(json) do
      {:ok, payload} ->
        case Event.from(payload) do
          nil ->
            Logger.warning("Received unrecognized event from Tap: #{inspect(payload)}")
            :noop

          event ->
            Event.dispatch(event, options, conn, stream)
            {:ok, data}
        end

      {:error, reason} ->
        Logger.error("Failed to decode JSON from Tap: #{inspect(reason)}")
        :noop
    end
  end

  @impl true
  def handle_frame({:binary, _binary}, _data) do
    Logger.warning("Received unexpected binary frame from Tap")
    :noop
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

  defp build_socket_opts(%Options{host: host, admin_password: admin_password} = options) do
    base_opts = [
      host: host,
      options: options
    ]

    if admin_password do
      auth_header = build_auth_header(admin_password)

      gun_opts = %{
        ws_opts: %{
          headers: [{"authorization", auth_header}]
        }
      }

      Keyword.put(base_opts, :gun_opts, gun_opts)
    else
      base_opts
    end
  end

  @spec build_auth_header(String.t()) :: String.t()
  defp build_auth_header(password) do
    credentials = "admin:#{password}"
    "Basic #{Base.encode64(credentials)}"
  end
end
