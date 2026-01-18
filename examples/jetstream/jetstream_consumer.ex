defmodule JetstreamConsumer do
  @moduledoc """
  Example Jetstream consumer implementation.

  This consumer demonstrates handling different types of Jetstream events:
  - Commit events (create, update, delete operations)
  - Identity events (handle changes, etc.)
  - Account events (status changes)
  """

  @behaviour Drinkup.Jetstream.Consumer

  def handle_event(%Drinkup.Jetstream.Event.Commit{operation: :create} = event) do
    IO.inspect(event, label: "New record created")
    :ok
  end

  def handle_event(%Drinkup.Jetstream.Event.Commit{operation: :update} = event) do
    IO.inspect(event, label: "Record updated")
    :ok
  end

  def handle_event(%Drinkup.Jetstream.Event.Commit{operation: :delete} = event) do
    IO.inspect(event, label: "Record deleted")
    :ok
  end

  def handle_event(%Drinkup.Jetstream.Event.Identity{} = event) do
    IO.inspect(event, label: "Identity updated")
    :ok
  end

  def handle_event(%Drinkup.Jetstream.Event.Account{active: false} = event) do
    IO.inspect(event, label: "Account inactive")
    :ok
  end

  def handle_event(%Drinkup.Jetstream.Event.Account{active: true} = event) do
    IO.inspect(event, label: "Account active")
    :ok
  end

  def handle_event(event) do
    IO.inspect(event, label: "Unknown event")
    :ok
  end
end

defmodule ExampleJetstreamSupervisor do
  @moduledoc """
  Example supervisor that starts a Jetstream connection.

  ## Usage

      # Start the supervisor
      {:ok, pid} = ExampleJetstreamSupervisor.start_link()

      # Update filters dynamically
      Drinkup.Jetstream.update_options(MyJetstream, %{
        wanted_collections: ["app.bsky.feed.post", "app.bsky.feed.like"]
      })

      # Stop the supervisor
      Supervisor.stop(pid)
  """

  use Supervisor

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      # Connect to public Jetstream instance and filter for posts and likes
      {Drinkup.Jetstream,
       %{
         consumer: JetstreamConsumer,
         name: MyJetstream,
         wanted_collections: ["app.bsky.feed.post", "app.bsky.feed.like"]
       }}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Example: Filter for all graph operations (follows, blocks, etc.)
defmodule GraphEventsConsumer do
  @behaviour Drinkup.Jetstream.Consumer

  def handle_event(%Drinkup.Jetstream.Event.Commit{collection: "app.bsky.graph." <> _} = event) do
    IO.puts("Graph event: #{event.collection} - #{event.operation}")
    :ok
  end

  def handle_event(_event), do: :ok
end

# Example: Filter for specific DIDs
defmodule SpecificDIDConsumer do
  @behaviour Drinkup.Jetstream.Consumer

  @watched_dids [
    "did:plc:abc123",
    "did:plc:def456"
  ]

  def handle_event(%Drinkup.Jetstream.Event.Commit{did: did} = event)
      when did in @watched_dids do
    IO.puts("Activity from watched DID: #{did}")
    IO.inspect(event)
    :ok
  end

  def handle_event(_event), do: :ok
end
