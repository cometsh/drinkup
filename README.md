# Drinkup

An Elixir library for consuming various AT Protocol sync services.

Drinkup provides a unified interface for connecting to various AT Protocol data
streams, handling reconnection logic, sequence tracking, and event dispatch.
Choose the sync service that fits your needs:

- **Firehose** - Raw event stream from the full AT Protocol network.
- **Jetstream** - Lightweight, cherry-picked event stream with filtering by
  record collections and DIDs.
- **Tap** - Managed backfill and indexing solution.

## Installation

Add `drinkup` to your `mix.exs`:

```elixir
def deps do
  [
    {:drinkup, "~> 0.2"}
  ]
end
```

Documentation can be found on HexDocs at https://hexdocs.pm/drinkup.

## Quick Start

### Firehose

```elixir
defmodule MyApp.FirehoseConsumer do
  use Drinkup.Firehose

  @impl true
  def handle_event(%Drinkup.Firehose.Event.Commit{} = event) do
    IO.inspect(event, label: "Commit")
  end

  def handle_event(_), do: :noop
end

# In your supervision tree:
children = [MyApp.FirehoseConsumer]
```

For filtered commit events by collection:

```elixir
defmodule MyApp.PostConsumer do
  use Drinkup.Firehose.RecordConsumer,
    collections: ["app.bsky.feed.post"]

  @impl true
  def handle_create(record) do
    IO.inspect(record, label: "New post")
  end
end
```

### Jetstream

```elixir
defmodule MyApp.JetstreamConsumer do
  use Drinkup.Jetstream,
    wanted_collections: ["app.bsky.feed.post"]

  @impl true
  def handle_event(%Drinkup.Jetstream.Event.Commit{} = event) do
    IO.inspect(event, label: "Commit")
  end

  def handle_event(_), do: :noop
end

# In your supervision tree:
children = [MyApp.JetstreamConsumer]

# Update filters dynamically:
Drinkup.Jetstream.update_options(MyApp.JetstreamConsumer, %{
  wanted_collections: ["app.bsky.graph.follow"]
})
```

### Tap

```elixir
defmodule MyApp.TapConsumer do
  use Drinkup.Tap,
    host: "http://localhost:2480"

  @impl true
  def handle_event(%Drinkup.Tap.Event.Record{} = event) do
    IO.inspect(event, label: "Record")
    :ok
  end

  def handle_event(_), do: :ok
end

# In your supervision tree:
children = [MyApp.TapConsumer]

# Track specific repos:
Drinkup.Tap.add_repos(MyTap.TapConsumer, ["did:plc:abc123"])
```

See [the examples](./examples) for some more complete samples.

## TODO

- Validation for Firehose events (signatures, active account tracking) — see
  [Firehose Validation Best Practices](https://atproto.com/specs/sync#firehose-validation-best-practices)
- Pluggable cursor persistence (Mnesia, Postgres, etc.)
- Multi-node/distribution testing
- More comprehensive test coverage
- Additional documentation

## Special thanks

The process structure used in Drinkup is heavily inspired by the work done on
[Nostrum](https://github.com/Kraigie/nostrum), an incredible Elixir library for
Discord.

## License

This project is licensed under the [MIT License](./LICENSE)
