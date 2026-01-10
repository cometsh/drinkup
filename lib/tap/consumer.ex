defmodule Drinkup.Tap.Consumer do
  @moduledoc """
  Consumer behaviour for handling Tap events.

  Implement this behaviour to process events from a Tap indexer/backfill service.
  Events are dispatched asynchronously via `Task.Supervisor` and acknowledged
  to Tap based on the return value of `handle_event/1`.

  ## Event Acknowledgment

  By default, events are acknowledged to Tap based on your return value:

  - `:ok`, `{:ok, any()}`, or `nil` → Success, event is acked to Tap
  - `{:error, reason}` → Failure, event is NOT acked (Tap will retry after timeout)
  - Exception raised → Failure, event is NOT acked (Tap will retry after timeout)

  Any other value will log a warning and acknowledge the event anyway.

  If you set `disable_acks: true` in your Tap options, no acks are sent regardless
  of the return value. This matches Tap's `TAP_DISABLE_ACKS` environment variable.

  ## Example

      defmodule MyTapConsumer do
        @behaviour Drinkup.Tap.Consumer

        def handle_event(%Drinkup.Tap.Event.Record{action: :create} = record) do
          # Handle new record creation
          case save_to_database(record) do
            :ok -> :ok  # Success - event will be acked
            {:error, reason} -> {:error, reason}  # Failure - Tap will retry
          end
        end

        def handle_event(%Drinkup.Tap.Event.Identity{} = identity) do
          # Handle identity changes
          update_identity(identity)
          :ok  # Success - event will be acked
        end
      end
  """

  alias Drinkup.Tap.Event

  @callback handle_event(Event.Record.t() | Event.Identity.t()) :: any()
end
