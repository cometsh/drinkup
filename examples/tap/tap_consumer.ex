defmodule TapConsumer do
  use Drinkup.Tap,
    name: MyTap,
    host: "http://localhost:2480"

  @impl true
  def handle_event(%Drinkup.Tap.Event.Record{} = record) do
    IO.inspect(record, label: "Tap record event")
    :ok
  end

  def handle_event(%Drinkup.Tap.Event.Identity{} = identity) do
    IO.inspect(identity, label: "Tap identity event")
    :ok
  end
end

defmodule ExampleTapConsumer do
  use Supervisor

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [TapConsumer]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
