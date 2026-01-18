defmodule Drinkup.Jetstream.Consumer do
  @moduledoc """
  Consumer behaviour for handling Jetstream events.

  Implement this behaviour to process events from a Jetstream instance.
  Events are dispatched asynchronously via `Task.Supervisor`.

  Unlike Tap, Jetstream does not require event acknowledgments. Events are
  processed in a fire-and-forget manner.

  ## Example

      defmodule MyJetstreamConsumer do
        @behaviour Drinkup.Jetstream.Consumer

        def handle_event(%Drinkup.Jetstream.Event.Commit{operation: :create} = event) do
          # Handle new record creation
          IO.inspect(event, label: "New record")
          :ok
        end

        def handle_event(%Drinkup.Jetstream.Event.Commit{operation: :delete} = event) do
          # Handle record deletion
          IO.inspect(event, label: "Deleted record")
          :ok
        end

        def handle_event(%Drinkup.Jetstream.Event.Identity{} = event) do
          # Handle identity changes
          IO.inspect(event, label: "Identity update")
          :ok
        end

        def handle_event(%Drinkup.Jetstream.Event.Account{active: false} = event) do
          # Handle account deactivation
          IO.inspect(event, label: "Account inactive")
          :ok
        end

        def handle_event(_event), do: :ok
      end

  ## Event Types

  The consumer will receive one of three event types:

  - `Drinkup.Jetstream.Event.Commit` - Repository commits (create, update, delete)
  - `Drinkup.Jetstream.Event.Identity` - Identity updates (handle changes, etc.)
  - `Drinkup.Jetstream.Event.Account` - Account status changes (active, taken down, etc.)

  ## Error Handling

  If your `handle_event/1` implementation raises an exception, it will be logged
  but will not affect the stream. The error is caught and logged by the event
  dispatcher.
  """

  alias Drinkup.Jetstream.Event

  @callback handle_event(Event.t()) :: any()
end
