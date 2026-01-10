defmodule Drinkup.Tap.Event do
  @moduledoc """
  Event handling and dispatch for Tap events.

  Parses incoming JSON events from Tap and dispatches them to the configured
  consumer via Task.Supervisor. After successful processing, sends an ack
  message back to the socket.
  """

  require Logger
  alias Drinkup.Tap.{Event, Options}

  @type t() :: Event.Record.t() | Event.Identity.t()

  @doc """
  Parse a JSON map into an event struct.

  Returns the appropriate event struct based on the "type" field.
  """
  @spec from(map()) :: t() | nil
  def from(%{"type" => "record"} = payload), do: Event.Record.from(payload)
  def from(%{"type" => "identity"} = payload), do: Event.Identity.from(payload)
  def from(_payload), do: nil

  @doc """
  Dispatch an event to the consumer via Task.Supervisor.

  Spawns a task that:
  1. Processes the event via the consumer's handle_event/1 callback
  2. Sends an ack to Tap if acks are enabled and the consumer returns :ok, {:ok, _}, or nil
  3. Does not ack if the consumer returns an error-like value or raises an exception

  Consumer return value semantics (when acks are enabled):
  - `:ok` or `{:ok, any()}` or `nil` -> Success, send ack
  - `{:error, _}` or any error-like tuple -> Failure, don't ack (Tap will retry)
  - Exception raised -> Failure, don't ack (Tap will retry)

  If `disable_acks: true` is set in options, no acks are sent regardless of
  consumer return value.
  """
  @spec dispatch(t(), Options.t(), pid(), :gun.stream_ref()) :: :ok
  def dispatch(
        event,
        %Options{consumer: consumer, name: name, disable_acks: disable_acks},
        conn,
        stream
      ) do
    supervisor_name = {:via, Registry, {Drinkup.Registry, {name, TapTasks}}}
    event_id = get_event_id(event)

    {:ok, _pid} =
      Task.Supervisor.start_child(supervisor_name, fn ->
        try do
          result = consumer.handle_event(event)

          unless disable_acks do
            case result do
              :ok ->
                send_ack(conn, stream, event_id)

              {:ok, _} ->
                send_ack(conn, stream, event_id)

              nil ->
                send_ack(conn, stream, event_id)

              :error ->
                Logger.error("Consumer returned error for event #{event_id}, not acking.")

              {:error, reason} ->
                Logger.error(
                  "Consumer returned error for event #{event_id}, not acking: #{inspect(reason)}"
                )

              _ ->
                Logger.warning(
                  "Consumer returned unexpected value for event #{event_id}, acking anyway: #{inspect(result)}"
                )

                send_ack(conn, stream, event_id)
            end
          end
        rescue
          e ->
            Logger.error(
              "Error in Tap event handler (event #{event_id}), not acking: #{Exception.format(:error, e, __STACKTRACE__)}"
            )
        end
      end)

    :ok
  end

  @spec send_ack(pid(), :gun.stream_ref(), integer()) :: :ok
  defp send_ack(conn, stream, event_id) do
    ack_message = Jason.encode!(%{type: "ack", id: event_id})

    :ok = :gun.ws_send(conn, stream, {:text, ack_message})
    Logger.debug("[Drinkup.Tap] Acked event #{event_id}")
  end

  @spec get_event_id(t()) :: integer()
  defp get_event_id(%Event.Record{id: id}), do: id
  defp get_event_id(%Event.Identity{id: id}), do: id
end
