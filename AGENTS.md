# AGENTS.md

This file provides guidance for agentic coding assistants working with the
Drinkup codebase.

## Project Overview

Drinkup is an Elixir library for consuming events from an ATProtocol relay
(firehose/`com.atproto.sync.subscribeRepos`). It uses OTP principles with
GenStatem for managing WebSocket connections and Task.Supervisor for concurrent
event processing.

## Build, Lint, and Test Commands

### Running Tests

```bash
# Run all tests
mix test

# Run a single test file
mix test test/drinkup_test.exs

# Run a specific test by line number
mix test test/drinkup_test.exs:5

# Run tests with coverage
mix test --cover

# Run tests matching a pattern
mix test --only [tag_name]
```

### Formatting and Linting

```bash
# Format code (uses .formatter.exs config)
mix format

# Check if code is formatted
mix format --check-formatted

# Run Credo for static code analysis
mix credo

# Run Credo strictly
mix credo --strict
```

### Compilation and Documentation

```bash
# Compile the project
mix compile

# Clean build artifacts
mix clean

# Generate documentation
mix docs

# Run Dialyzer for type checking (if configured)
mix dialyzer
```

## Code Style Guidelines

### Module Structure

- Use `defmodule` with clear, descriptive names following `Drinkup.<Component>`
  namespace
- Place module documentation (`@moduledoc`) immediately after `defmodule`
- Group related functionality within nested modules (e.g.,
  `Drinkup.Event.Commit.RepoOp`)
- Order module contents: module attributes, types, public functions, private
  functions

### Imports and Aliases

- Use `require` for macros (e.g., `require Logger`)
- Use `alias` to shorten module names, prefer explicit aliases over `import`
- Group in order: `require`, `alias`, `import`
- Example:
  ```elixir
  require Logger
  alias Drinkup.{Event, Options}
  ```

### Type Specifications

- Use TypedStruct for structs with typed fields (dependency:
  `{:typedstruct, "~> 0.5"}`)
- Define `@type` specs for complex types, unions, and public APIs
- Use `@spec` for all public functions
- Use `enforce: true` for required TypedStruct fields
- Example:

  ```elixir
  use TypedStruct

  typedstruct enforce: true do
    field :consumer, module()
    field :name, atom(), default: Drinkup
    field :cursor, pos_integer() | nil, enforce: false
  end
  ```

### Naming Conventions

- Modules: PascalCase (`Drinkup.Event.Commit`)
- Functions: snake_case (`handle_event/1`, `from/1`)
- Variables: snake_case (`repo_op`, `last_seq`)
- Private functions: prefix with `defp`, mark with `@spec` if complex
- Atoms: lowercase with underscores (`:ok`, `:connect_timeout`)
- Behaviours: use `@behaviour` (not `@behavior`)

### Function Definitions

- Pattern match in function heads when possible
- Use guard clauses for simple type/value checks
- Prefer multiple function heads over large case statements
- Example:
  ```elixir
  def valid_seq?(nil, seq) when is_integer(seq), do: true
  def valid_seq?(last_seq, nil) when is_integer(last_seq), do: true
  def valid_seq?(last_seq, seq) when is_integer(last_seq) and is_integer(seq),
    do: seq > last_seq
  def valid_seq?(_last_seq, _seq), do: false
  ```

### Error Handling

- Use `try/rescue` for expected errors, catch and log appropriately
- Use Logger for errors:
  `Logger.error("Message: #{Exception.format(:error, e, __STACKTRACE__)}")`
- Return tagged tuples: `{:ok, result}` or `{:error, reason}`
- Use `with` for chaining operations that may fail
- Example from Socket module:
  ```elixir
  with {:ok, header, next} <- CAR.DagCbor.decode(frame),
       {:ok, payload, _} <- CAR.DagCbor.decode(next),
       {%{"op" => @op_regular}, _} <- {header, payload} do
    # happy path
  else
    {:error, reason} -> Logger.warning("Failed to decode: #{inspect(reason)}")
  end
  ```

### OTP and Concurrency Patterns

- Use `child_spec/1` for custom supervisor specifications
- Prefer `GenServer` for stateful processes, `:gen_statem` for state machines
- Use `Task.Supervisor` for concurrent, fire-and-forget work (see
  `Event.dispatch/2`)
- Register processes via Registry for named lookups
- Define proper restart strategies (`:permanent`, `:transient`, `:temporary`)

### Comments

- Avoid obvious comments; prefer self-documenting code
- Use `# TODO:` for future improvements (see existing TODOs in codebase)
- Use `# DEPRECATED` for deprecated fields (see Commit struct)
- Document complex algorithms or non-obvious business logic
- Use module-level `@moduledoc` and function-level `@doc` for public APIs

### Formatting

- Use `mix format` (configured in `.formatter.exs`)
- Import deps for formatting: `import_deps: [:typedstruct]`
- Line length: default Elixir formatter settings
- Use 2-space indentation (enforced by formatter)

### Testing

- Use ExUnit for tests (files in `test/` with `_test.exs` suffix)
- Use `use ExUnit.Case` in test modules
- Use `doctest Module` for testing documentation examples
- Tag tests for selective running: `@tag :integration`
- Use descriptive test names: `test "validates sequence numbers correctly"`

## Project-Specific Patterns

### Consumer Behaviour Pattern

- Implement `@behaviour Drinkup.Consumer` with `handle_event/1` callback
- Use pattern matching to handle different event types
- Return any value; errors are caught by Task.Supervisor wrapper

### RecordConsumer Macro Pattern

- Use `use Drinkup.RecordConsumer` with `collections:` opt for filtering
- Override `handle_create/1`, `handle_update/1`, `handle_delete/1` as needed
- Collections can be exact strings or Regex patterns: `~r/app\.bsky\.graph\..+/`

### WebSocket State Machine

- Socket module uses `:gen_statem` with states: `:disconnected`,
  `:connecting_http`, `:connecting_ws`, `:connected`
- State functions match on events: `state_name(:enter, from, data)` or
  `state_name(:info, msg, data)`
- Use `{:next_event, :internal, event}` for internal state transitions

## Dependencies

- `{:gun, "~> 2.2"}` - HTTP/WebSocket client
- `{:car, "~> 0.1.0"}` - CAR (Content Addressable aRchive) format
- `{:cbor, "~> 1.0.0"}` - CBOR encoding/decoding
- `{:typedstruct, "~> 0.5"}` - Typed structs
- `{:credo, "~> 1.7"}` - Static analysis (dev/test only)

## Common Tasks

### Adding a New Event Type

1. Create `lib/event/your_event.ex` with TypedStruct definition
2. Add `from/1` function to parse payload
3. Add pattern match in `Drinkup.Event.from/2`
4. Add to `@type t()` union in `Drinkup.Event`
5. Update `CHANGELOG.md` under `[Unreleased]` section with the new feature

### Debugging Connection Issues

- Check `:gun` connection logs in Socket module
- Verify sequence tracking with `Event.valid_seq?/2`
- Monitor state transitions: `:disconnected` → `:connecting_http` →
  `:connecting_ws` → `:connected`

## Changelog Management

**IMPORTANT**: After completing any feature or fixing a bug from a previous
release, you MUST update `CHANGELOG.md`.

### Changelog Format

- Follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format
- Uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
- Group changes under appropriate sections: `Added`, `Changed`, `Deprecated`,
  `Removed`, `Fixed`, `Security`

### When to Update

- **New features**: Add under `## [Unreleased]` → `### Added`
- **Bug fixes**: Add under `## [Unreleased]` → `### Fixed`
- **Breaking changes**: Add under `## [Unreleased]` → `### Breaking Changes`
- **Deprecations**: Add under `## [Unreleased]` → `### Deprecated`
- **Security fixes**: Add under `## [Unreleased]` → `### Security`

### Example Entry

```markdown
## [Unreleased]

### Added

- Support for `#handle` event type in firehose consumer

### Fixed

- Sequence validation now correctly handles nil cursor on initial connection
```
