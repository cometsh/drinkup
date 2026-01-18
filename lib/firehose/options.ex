defmodule Drinkup.Firehose.Options do
  @moduledoc """
  Configuration options for ATProto Firehose relay subscriptions.

  This module defines the configuration structure for connecting to and
  consuming events from an ATProto Firehose relay. The Firehose streams
  real-time repository events from the AT Protocol network.

  ## Options

  - `:consumer` (required) - Module implementing `Drinkup.Firehose.Consumer` behaviour
  - `:name` - Unique name for this Firehose instance in the supervision tree (default: `Drinkup.Firehose`)
  - `:host` - Firehose relay URL (default: `"https://bsky.network"`)
  - `:cursor` - Optional sequence number to resume streaming from

  ## Example

      %{
        consumer: MyFirehoseConsumer,
        name: MyFirehose,
        host: "https://bsky.network",
        cursor: 12345
      }
  """

  use TypedStruct

  @default_host "https://bsky.network"

  @typedoc """
  Map of configuration options accepted by `Drinkup.Firehose.child_spec/1`.
  """
  @type options() :: %{
          required(:consumer) => consumer(),
          optional(:name) => name(),
          optional(:host) => host(),
          optional(:cursor) => cursor()
        }

  @typedoc """
  Module implementing the `Drinkup.Firehose.Consumer` behaviour.
  """
  @type consumer() :: module()

  @typedoc """
  Unique identifier for this Firehose instance in the supervision tree.

  Used for Registry lookups and naming child processes.
  """
  @type name() :: atom()

  @typedoc """
  HTTP/HTTPS URL of the ATProto Firehose relay.

  Defaults to `"https://bsky.network"` which is the public Bluesky relay.

  You can find a list of third-party relays at https://compare.hose.cam/.
  """
  @type host() :: String.t()

  @typedoc """
  Optional sequence number to resume streaming from.

  When provided, the Firehose will replay events starting from this sequence
  number. Useful for resuming after a restart without missing events. The
  cursor is automatically tracked and updated as events are received.
  """
  @type cursor() :: pos_integer() | nil

  typedstruct do
    field :consumer, consumer(), enforce: true
    field :name, name(), default: Drinkup.Firehose
    field :host, host(), default: @default_host
    field :cursor, cursor()
  end

  @spec from(options()) :: t()
  def from(%{consumer: _} = options), do: struct(__MODULE__, options)
end
