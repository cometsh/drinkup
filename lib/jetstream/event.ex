defmodule Drinkup.Jetstream.Event do
  @moduledoc """
  Event handling and dispatch for Jetstream events.

  Parses incoming JSON events from Jetstream and dispatches them to the
  configured consumer via Task.Supervisor.
  """

  require Logger
  alias Drinkup.Jetstream.{Event, Options}

  @type t() :: Event.Commit.t() | Event.Identity.t() | Event.Account.t()

  @doc """
  Parse a JSON map into an event struct.

  Jetstream events have a top-level structure with a "kind" field that
  determines the event type, and a nested object with the event data.

  ## Example Event Structure

      %{
        "did" => "did:plc:...",
        "time_us" => 1726880765818347,
        "kind" => "commit",
        "commit" => %{...}
      }

  Returns the appropriate event struct based on the "kind" field, or `nil`
  if the event type is not recognized.
  """
  @spec from(map()) :: t() | nil
  def from(%{"did" => did, "time_us" => time_us, "kind" => kind} = payload) do
    case kind do
      "commit" ->
        case Map.get(payload, "commit") do
          nil ->
            Logger.warning("Commit event missing 'commit' field: #{inspect(payload)}")
            nil

          commit ->
            Event.Commit.from(did, time_us, commit)
        end

      "identity" ->
        case Map.get(payload, "identity") do
          nil ->
            Logger.warning("Identity event missing 'identity' field: #{inspect(payload)}")
            nil

          identity ->
            Event.Identity.from(did, time_us, identity)
        end

      "account" ->
        case Map.get(payload, "account") do
          nil ->
            Logger.warning("Account event missing 'account' field: #{inspect(payload)}")
            nil

          account ->
            Event.Account.from(did, time_us, account)
        end

      _ ->
        Logger.warning("Received unrecognized event kind from Jetstream: #{inspect(kind)}")
        nil
    end
  end

  def from(payload) do
    Logger.warning("Received invalid event structure from Jetstream: #{inspect(payload)}")
    nil
  end

  @doc """
  Dispatch an event to the consumer via Task.Supervisor.

  Spawns a task that processes the event via the consumer's `handle_event/1`
  callback. Unlike Tap, Jetstream does not require acknowledgments.
  """
  @spec dispatch(t(), Options.t()) :: :ok
  def dispatch(event, %Options{consumer: consumer, name: name}) do
    supervisor_name = {:via, Registry, {Drinkup.Registry, {name, JetstreamTasks}}}

    {:ok, _pid} =
      Task.Supervisor.start_child(supervisor_name, fn ->
        try do
          consumer.handle_event(event)
        rescue
          e ->
            Logger.error(
              "Error in Jetstream event handler: #{Exception.format(:error, e, __STACKTRACE__)}"
            )
        end
      end)

    :ok
  end
end
