# Agent Guidelines for Drinkup

## Commands

- **Test**: `mix test` (all), `mix test test/path/to/file_test.exs` (single file), `mix test test/path/to/file_test.exs:42` (single test at line)
- **Format**: `mix format` (auto-formats all code)
- **Lint**: `mix credo` (static analysis), `mix credo --strict` (strict mode)
- **Compile**: `mix compile`
- **Docs**: `mix docs`
- **Type Check**: `mix dialyzer` (if configured)

## Code Style

- **Imports**: Use `alias` for modules (e.g., `alias Drinkup.Firehose.{Event, Options}`), `require` for macros (e.g., `require Logger`)
- **Formatting**: Elixir 1.18+, auto-formatted via `.formatter.exs` with `import_deps: [:typedstruct]`
- **Naming**: snake_case for functions/variables, PascalCase for modules, `:lowercase_atoms` for atoms, `@behaviour` (not `@behavior`)
- **Types**: Use `@type` and `@spec` for all functions; use TypedStruct for structs with `enforce: true` for required fields
- **Moduledocs**: Public modules need `@moduledoc`, public functions need `@doc` with examples
- **Error Handling**: Return `{:ok, result}` or `{:error, reason}` tuples; use `with` for chaining operations; log errors with `Logger.error("#{Exception.format(:error, e, __STACKTRACE__)}")`
- **Pattern Matching**: Prefer pattern matching in function heads over conditionals; use guard clauses when appropriate
- **OTP**: Use `child_spec/1` for custom supervisor specs; `:gen_statem` for state machines; `Task.Supervisor` for concurrent tasks; Registry for named lookups
- **Tests**: Use ExUnit with `use ExUnit.Case`; use `doctest Module` for documentation examples
- **Dependencies**: Core deps include gun (WebSocket), car (CAR format), cbor (encoding), TypedStruct (typed structs), Credo (linting)

## Project Structure

Each namespace (`Drinkup.Firehose`, `Drinkup.Jetstream`, `Drinkup.Tap`) follows a common architecture:

- **Core Modules**:
  - `Consumer` - Behaviour/macro for handling events; `use Namespace` with `handle_event/1` implementation
  - `Event` - Typed event structs specific to the protocol
  - `Socket` - `:gen_statem` WebSocket connection manager
  - `Options` (or top-level utility module) - Configuration and runtime utilities

- **Consumer Pattern**: `use Namespace, opts...` with `handle_event/1` callback; consumer module becomes a supervisor

### Namespace-Specific Details

- **Firehose** (`Drinkup.Firehose.*`): Full AT Protocol firehose
  - Events: `Commit`, `Sync`, `Identity`, `Account`, `Info`
  - Additional: `RecordConsumer` macro for filtered commit records with `handle_create/1`, `handle_update/1`, `handle_delete/1` callbacks
  - Pattern: `use Drinkup.Firehose.RecordConsumer, collections: [~r/app\.bsky\.graph\..+/, "app.bsky.feed.post"]`

- **Jetstream** (`Drinkup.Jetstream.*`): Simplified JSON event stream
  - Events: `Commit`, `Identity`, `Account`
  - Config: `:wanted_collections`, `:wanted_dids`, `:compress` (zstd)
  - Utility: `Drinkup.Jetstream.update_options/2` for dynamic filtering
  - Semantics: Fire-and-forget (no acks)

- **Tap** (`Drinkup.Tap.*`): HTTP API + WebSocket indexer/backfill service
  - Events: `Record`, `Identity`
  - Config: `:host`, `:admin_password`, `:disable_acks`
  - Utility: `Drinkup.Tap` HTTP API functions (`add_repos/2`, `remove_repos/2`, `get_repo_info/2`)
  - Semantics: Ack/nack - return `:ok`/`{:ok, _}`/`nil` to ack, `{:error, _}` to nack (Tap retries)

## Important Notes

- **Update CHANGELOG.md** when adding features, changes, or fixes under `## [Unreleased]` with appropriate sections (`Added`, `Changed`, `Fixed`, `Deprecated`, `Removed`, `Security`)
- **WebSocket States**: Socket uses `:disconnected` → `:connecting_http` → `:connecting_ws` → `:connected` flow
- **Sequence Tracking**: Use `Event.valid_seq?/2` to validate sequence numbers from firehose
