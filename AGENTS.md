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

- **Namespace**: All firehose functionality under `Drinkup.Firehose.*`
  - `Drinkup.Firehose` - Main supervisor
  - `Drinkup.Firehose.Consumer` - Behaviour for handling all events
  - `Drinkup.Firehose.RecordConsumer` - Macro for handling commit record events with filtering
  - `Drinkup.Firehose.Event` - Event types (`Commit`, `Sync`, `Identity`, `Account`, `Info`)
  - `Drinkup.Firehose.Socket` - `:gen_statem` WebSocket connection manager
- **Consumer Pattern**: Implement `@behaviour Drinkup.Firehose.Consumer` with `handle_event/1`
- **RecordConsumer Pattern**: `use Drinkup.Firehose.RecordConsumer, collections: [~r/app\.bsky\.graph\..+/, "app.bsky.feed.post"]` with `handle_create/1`, `handle_update/1`, `handle_delete/1` overrides

## Important Notes

- **Update CHANGELOG.md** when adding features, changes, or fixes under `## [Unreleased]` with appropriate sections (`Added`, `Changed`, `Fixed`, `Deprecated`, `Removed`, `Security`)
- **WebSocket States**: Socket uses `:disconnected` → `:connecting_http` → `:connecting_ws` → `:connected` flow
- **Sequence Tracking**: Use `Event.valid_seq?/2` to validate sequence numbers from firehose
