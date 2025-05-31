defmodule PostDeleteConsumer do
  use Drinkup.RecordConsumer, collections: ["app.bsky.feed.post"]

  def handle_delete(record) do
    IO.inspect(record, label: "update")
  end
end

defmodule IdentityConsumer do
  @behaviour Drinkup.Consumer

  def handle_event(%Drinkup.Event.Identity{} = event) do
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
      {Drinkup, %{consumer: PostDeleteConsumer}},
      {Drinkup, %{consumer: IdentityConsumer, name: :identities}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
