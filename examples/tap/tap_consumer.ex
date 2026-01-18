defmodule TapConsumer do
  @behaviour Drinkup.Tap.Consumer

  def handle_event(%Drinkup.Tap.Event.Record{} = record) do
    IO.inspect(record, label: "Tap record event")
  end

  def handle_event(%Drinkup.Tap.Event.Identity{} = identity) do
    IO.inspect(identity, label: "Tap identity event")
  end
end

defmodule TapExampleSupervisor do
  use Supervisor

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Drinkup.Tap,
       %{
         consumer: TapConsumer,
         name: MyTap,
         host: "http://localhost:2480"
       }}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
