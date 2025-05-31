defmodule BasicConsumer do
  @behaviour Drinkup.Consumer

  def handle_event(%Drinkup.Event.Commit{} = event) do
    IO.inspect(event, label: "Got commit event")
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
      {Drinkup, %{consumer: BasicConsumer}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
