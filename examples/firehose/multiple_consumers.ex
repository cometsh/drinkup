defmodule PostDeleteConsumer do
  use Drinkup.Firehose.RecordConsumer, collections: ["app.bsky.feed.post"]

  def handle_delete(record) do
    IO.inspect(record, label: "update")
  end
end

defmodule IdentityConsumer do
  use Drinkup.Firehose, name: :identities

  @impl true
  def handle_event(%Drinkup.Firehose.Event.Identity{} = event) do
    IO.inspect(event, label: "identity event")
  end

  def handle_event(_), do: :noop
end

defmodule ExampleSupervisor do
  use Supervisor

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      PostDeleteConsumer,
      IdentityConsumer
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
