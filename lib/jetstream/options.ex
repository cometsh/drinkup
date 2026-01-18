defmodule Drinkup.Jetstream.Options do
  @moduledoc """
  Configuration options for Jetstream event stream connection.

  Jetstream is a simplified JSON event stream that converts the CBOR-encoded
  ATProto Firehose into lightweight, friendly JSON. It provides zstd compression
  and filtering capabilities for collections and DIDs.

  ## Options

  - `:consumer` (required) - Module implementing `Drinkup.Jetstream.Consumer` behaviour
  - `:name` - Unique name for this Jetstream instance in the supervision tree (default: `Drinkup.Jetstream`)
  - `:host` - Jetstream service URL (default: `"wss://jetstream2.us-east.bsky.network"`)
  - `:wanted_collections` - List of collection NSIDs or prefixes to filter (default: `[]` = all collections)
  - `:wanted_dids` - List of DIDs to filter (default: `[]` = all repos)
  - `:cursor` - Unix microseconds timestamp to resume from (default: `nil` = live-tail)
  - `:require_hello` - Pause replay until first options update is sent (default: `false`)
  - `:max_message_size_bytes` - Maximum message size to receive (default: `nil` = no limit)

  ## Example

      %{
        consumer: MyJetstreamConsumer,
        name: MyJetstream,
        host: "wss://jetstream2.us-east.bsky.network",
        wanted_collections: ["app.bsky.feed.post", "app.bsky.feed.like"],
        wanted_dids: ["did:plc:abc123"],
        cursor: 1725519626134432
      }

  ## Collection Filters

  The `wanted_collections` option supports:
  - Full NSIDs: `"app.bsky.feed.post"`
  - NSID prefixes: `"app.bsky.graph.*"`, `"app.bsky.*"`

  You can specify up to 100 collection filters.

  ## DID Filters

  The `wanted_dids` option accepts a list of DID strings.
  You can specify up to 10,000 DIDs.

  ## Compression

  Jetstream always uses zstd compression with a custom dictionary.
  This is handled automatically by the socket implementation.
  """

  use TypedStruct

  @default_host "wss://jetstream2.us-east.bsky.network"

  @typedoc """
  Map of configuration options accepted by `Drinkup.Jetstream.child_spec/1`.
  """
  @type options() :: %{
          required(:consumer) => consumer(),
          optional(:name) => name(),
          optional(:host) => host(),
          optional(:wanted_collections) => wanted_collections(),
          optional(:wanted_dids) => wanted_dids(),
          optional(:cursor) => cursor(),
          optional(:require_hello) => require_hello(),
          optional(:max_message_size_bytes) => max_message_size_bytes()
        }

  @typedoc """
  Module implementing the `Drinkup.Jetstream.Consumer` behaviour.
  """
  @type consumer() :: module()

  @typedoc """
  Unique identifier for this Jetstream instance in the supervision tree.

  Used for Registry lookups and naming child processes.
  """
  @type name() :: atom()

  @typedoc """
  WebSocket URL of the Jetstream service.

  Defaults to `"wss://jetstream2.us-east.bsky.network"` which is a public Bluesky instance.
  """
  @type host() :: String.t()

  @typedoc """
  List of collection NSIDs or NSID prefixes to filter.

  Examples:
  - `["app.bsky.feed.post"]` - Only posts
  - `["app.bsky.graph.*"]` - All graph collections
  - `["app.bsky.*"]` - All Bluesky app collections

  You can specify up to 100 collection filters.
  Defaults to `[]` (all collections).
  """
  @type wanted_collections() :: [String.t()]

  @typedoc """
  List of DIDs to filter events by.

  You can specify up to 10,000 DIDs.
  Defaults to `[]` (all repos).
  """
  @type wanted_dids() :: [String.t()]

  @typedoc """
  Unix microseconds timestamp to resume streaming from.

  When provided, Jetstream will replay events starting from this timestamp.
  Useful for resuming after a restart without missing events. The cursor is
  automatically tracked and updated as events are received.

  Defaults to `nil` (live-tail from current time).
  """
  @type cursor() :: pos_integer() | nil

  @typedoc """
  Whether to pause replay/live-tail until the first options update is sent.

  When `true`, the connection will wait for a `Drinkup.Jetstream.update_options/2`
  call before starting to receive events.

  Defaults to `false`.
  """
  @type require_hello() :: boolean()

  @typedoc """
  Maximum message size in bytes that the client would like to receive.

  Zero or `nil` means no limit. Negative values are treated as zero.
  Defaults to `nil` (no maximum size).
  """
  @type max_message_size_bytes() :: integer() | nil

  typedstruct do
    field :consumer, consumer(), enforce: true
    field :name, name(), default: Drinkup.Jetstream
    field :host, host(), default: @default_host
    # TODO: Add NSID prefix validation once available in atex
    field :wanted_collections, wanted_collections(), default: []
    field :wanted_dids, wanted_dids(), default: []
    field :cursor, cursor()
    field :require_hello, require_hello(), default: false
    field :max_message_size_bytes, max_message_size_bytes()
  end

  @spec from(options()) :: t()
  def from(%{consumer: _} = options), do: struct(__MODULE__, options)
end
