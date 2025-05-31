defmodule ExampleRecordConsumer do
  use Drinkup.RecordConsumer, collections: [~r/app\.bsky\.graph\..+/, "app.bsky.feed.post"]

  def handle_create(record) do
    IO.inspect(record, label: "create")
  end

  def handle_update(record) do
    IO.inspect(record, label: "update")
  end

  def handle_delete(record) do
    IO.inspect(record, label: "delete")
  end
end

defmodule ExampleSupervisor do
  use Supervisor

  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      {Drinkup, %{consumer: ExampleRecordConsumer}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
