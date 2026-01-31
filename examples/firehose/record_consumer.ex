defmodule ExampleRecordConsumer do
  use Drinkup.Firehose.RecordConsumer,
    collections: [~r/app\.bsky\.graph\..+/, "app.bsky.feed.post"]

  @impl true
  def handle_create(record) do
    IO.inspect(record, label: "create")
  end

  @impl true
  def handle_update(record) do
    IO.inspect(record, label: "update")
  end

  @impl true
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
    children = [ExampleRecordConsumer]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
