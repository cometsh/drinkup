defmodule Drinkup.Tap.Options do
  @moduledoc """
  Configuration options for Tap indexer/backfill service connection.

  This module defines the configuration structure for connecting to and
  interacting with a Tap service. Tap simplifies AT Protocol sync by handling
  firehose connections, verification, backfill, and filtering server-side.

  ## Options

  - `:consumer` (required) - Module implementing `Drinkup.Tap.Consumer` behaviour
  - `:name` - Unique name for this Tap instance in the supervision tree (default: `Drinkup.Tap`)
  - `:host` - Tap service URL (default: `"http://localhost:2480"`)
  - `:admin_password` - Optional password for authenticated Tap instances
  - `:disable_acks` - Disable event acknowledgments (default: `false`)

  ## Example

      %{
        consumer: MyTapConsumer,
        name: MyTap,
        host: "http://localhost:2480",
        admin_password: "secret",
        disable_acks: false
      }
  """

  use TypedStruct

  @default_host "http://localhost:2480"

  @typedoc """
  Map of configuration options accepted by `Drinkup.Tap.child_spec/1`.
  """
  @type options() :: %{
          required(:consumer) => consumer(),
          optional(:name) => name(),
          optional(:host) => host(),
          optional(:admin_password) => admin_password(),
          optional(:disable_acks) => disable_acks()
        }

  @typedoc """
  Module implementing the `Drinkup.Tap.Consumer` behaviour.
  """
  @type consumer() :: module()

  @typedoc """
  Unique identifier for this Tap instance in the supervision tree.

  Used for Registry lookups and naming child processes.
  """
  @type name() :: atom()

  @typedoc """
  HTTP/HTTPS URL of the Tap service.

  Defaults to `"http://localhost:2480"` which is Tap's default bind address.
  """
  @type host() :: String.t()

  @typedoc """
  Optional password for HTTP Basic authentication.

  Required when connecting to a Tap service configured with `TAP_ADMIN_PASSWORD`.
  The password is sent as `Basic admin:<password>` in the Authorization header.
  """
  @type admin_password() :: String.t() | nil

  @typedoc """
  Whether to disable event acknowledgments.

  When `true`, events are not acknowledged to Tap regardless of consumer
  return values. This matches Tap's `TAP_DISABLE_ACKS` environment variable.

  Defaults to `false` (acknowledgments enabled).
  """
  @type disable_acks() :: boolean()

  typedstruct do
    field :consumer, consumer(), enforce: true
    field :name, name(), default: Drinkup.Tap
    field :host, host(), default: @default_host
    field :admin_password, admin_password()
    field :disable_acks, disable_acks(), default: false
  end

  @spec from(options()) :: t()
  def from(%{consumer: _} = options), do: struct(__MODULE__, options)
end
