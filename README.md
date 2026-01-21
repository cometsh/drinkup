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
    {:drinkup, "~> 0.1"}
  ]
end
```

Documentation can be found on HexDocs at https://hexdocs.pm/drinkup.

## Quick Start

### Firehose

```elixir
defmodule MyApp.FirehoseConsumer do
  @behaviour Drinkup.Firehose.Consumer

  def handle_event(%Drinkup.Firehose.Event.Commit{} = event) do
    IO.inspect(event, label: "Commit")
  end

  def handle_event(_), do: :noop
end

# In your supervision tree:
children = [{Drinkup.Firehose, %{consumer: MyApp.FirehoseConsumer}}]
```

### Jetstream

```elixir
defmodule MyApp.JetstreamConsumer do
  @behaviour Drinkup.Jetstream.Consumer

  def handle_event(%Drinkup.Jetstream.Event.Commit{} = event) do
    IO.inspect(event, label: "Commit")
  end

  def handle_event(_), do: :noop
end

# In your supervision tree:
children = [
  {Drinkup.Jetstream, %{
    consumer: MyApp.JetstreamConsumer,
    wanted_collections: ["app.bsky.feed.post"]
  }}
]
```

### Tap

```elixir
defmodule MyApp.TapConsumer do
  @behaviour Drinkup.Tap.Consumer

  def handle_event(%Drinkup.Tap.Event.Record{} = event) do
    IO.inspect(event, label: "Record")
  end

  def handle_event(_), do: :noop
end

# In your supervision tree:
children = [
  {Drinkup.Tap, %{
    consumer: MyApp.TapConsumer,
    host: "http://localhost:2480"
  }}
]

# Track specific repos:
Drinkup.Tap.add_repos(Drinkup.Tap, ["did:plc:abc123"])
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
