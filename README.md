# Drinkup

An Elixir library for listening to events from an ATProtocol relay
(firehose/`com.atproto.sync.subscribeRepos`). Eventually aiming to support any
ATProtocol subscription.

## TODO

- Support for different subscriptions other than
  `com.atproto.sync.subscribeRepo'.
- Validation (signatures, making sure to only track handle active accounts,
  etc.) (see
  [Firehose Validation Best Practices](https://atproto.com/specs/sync#firehose-validation-best-practices))
- Look into backfilling? See if there's better ways to do it.
- Built-in solutions for tracking resumption? (probably a pluggable solution to
  allow for different things like Mnesia, Postgres, etc.)
- Testing of multi-node/distribution.
- Tests
- Documentation

## Installation

Add `drinkup` to your `mix.exs`.

```elixir
def deps do
  [
    {:drinkup, "~> 0.1"}
  ]
end
```

Documentation can be found on HexDocs at https://hexdocs.pm/drinkup.

## Example Usage

First, create a module implementing the `Drinkup.Consumer` behaviour (only
requires a `handle_event/1` function):

```elixir
defmodule ExampleConsumer do
  @behaviour Drinkup.Consumer

  def handle_event(%Drinkup.Event.Commit{} = event) do
    IO.inspect(event, label: "Got commit event")
  end

  def handle_event(_), do: :noop
end
```

Then add Drinkup and your consumer to your application's supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [{Drinkup, %{consumer: ExampleConsumer}}]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

You should then be able to start your application and start seeing
`Got commit event: ...` in the terminal.

### Record Consumer

One of the main reasons for listening to an ATProto relay is to synchronise a
database with records. As a result, Drinkup provides a light extension around a
basic consumer, the `RecordConsumer`, which only listens to commit events, and
transforms them into a slightly nicer structure to work around, calling your
`handle_create/1`, `handle_update/1`, and `handle_delete/1` functions for each
record it comes across. It also allows for filtering of specific types of
records either by full name or with a
[Regex](https://hexdocs.pm/elixir/1.18.4/Regex.html) match.

```elixir
defmodule ExampleRecordConsumer do
  # Will respond to any events either `app.bsky.feed.post` records, or anything under `app.bsky.graph`.
  use Drinkup.RecordConsumer, collections: [~r/app\.bsky\.graph\..+/, "app.bsky.feed.post"]
  alias Drinkup.RecordConsumer.Record

  def handle_create(%Record{type: "app.bsky.feed.post"} = record) do
    IO.inspect(record, label: "Bluesky post created")
  end

  def handle_create(%Record{type: "app.bsky.graph" <> _} = record) do
    IO.inspect(record, label: "Bluesky graph updated")
  end

  def handle_update(record) do
    # ...
  end

  def handle_delete(record) do
    # ...
  end
end
```

## Special thanks

The process structure used in Drinkup is heavily inspired by the work done on
[Nostrum](https://github.com/Kraigie/nostrum), an incredible Elixir library for
Discord.

## License

This project is licensed under the [MIT License](./LICENSE)
