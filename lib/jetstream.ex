defmodule Drinkup.Jetstream do
  @moduledoc """
  Module for handling events from an AT Protocol
  [Jetstream](https://github.com/bluesky-social/jetstream) instance.

  Jetstream is an abstraction over the raw AT Protocol firehose that converts
  the CBOR-encoded events into easier to handle JSON objects, and also provides
  the ability to filter the events received by repository DID or collection
  NSID. This is useful when you know specifically which repos or collections you
  want events from, and thus reduces the amount of bandwidth consumed vs
  consuming the raw firehose directly.

  If you need a solution for easy backfilling from repositories and not just a
  firehose translation layer, check out `Drinkup.Tap`.

  ## Usage

      defmodule MyJetstreamConsumer do
        use Drinkup.Jetstream,
          name: :my_jetstream,
          wanted_collections: ["app.bsky.feed.post"]

        @impl true
        def handle_event(event) do
          IO.inspect(event)
        end
      end

      # In your application supervision tree:
      children = [MyJetstreamConsumer]

  ## Configuration

  See `Drinkup.Jetstream.Consumer` for all available configuration options.

  ## Dynamic Filter Updates

  You can update filters after the connection is established:

      Drinkup.Jetstream.update_options(:my_jetstream, %{
        wanted_collections: ["app.bsky.graph.follow"],
        wanted_dids: ["did:plc:abc123"]
      })

  ## Public Instances

  By default Drinkup connects to `jetstream2.us-east.bsky.network`.

  Bluesky operates a few different Jetstream instances:
  - `wss://jetstream1.us-east.bsky.network`
  - `wss://jetstream2.us-east.bsky.network`
  - `wss://jetstream1.us-west.bsky.network`
  - `wss://jetstream2.us-west.bsky.network`

  There also some third-party instances not run by Bluesky PBC, including but not limited to:
  - `wss://jetstream.fire.hose.cam`
  - `wss://jetstream2.fr.hose.cam`
  - `wss://jetstream1.us-east.fire.hose.cam`

  https://firehose.stream/ also hosts several instances around the world.
  """

  require Logger

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use Supervisor
      @behaviour Drinkup.Jetstream.Consumer

      alias Drinkup.Jetstream.Options

      # Store compile-time options as module attributes
      @name Keyword.get(opts, :name)
      @host Keyword.get(opts, :host, "wss://jetstream2.us-east.bsky.network")
      @wanted_collections Keyword.get(opts, :wanted_collections, [])
      @wanted_dids Keyword.get(opts, :wanted_dids, [])
      @cursor Keyword.get(opts, :cursor)
      @require_hello Keyword.get(opts, :require_hello, false)
      @max_message_size_bytes Keyword.get(opts, :max_message_size_bytes)

      @doc """
      Starts the Jetstream consumer supervisor.

      Accepts optional runtime configuration that overrides compile-time options.
      """
      def start_link(runtime_opts \\ []) do
        opts = build_options(runtime_opts)
        Supervisor.start_link(__MODULE__, opts, name: via_tuple(opts.name))
      end

      @impl true
      def init(%Options{name: name} = options) do
        children = [
          {Task.Supervisor, name: {:via, Registry, {Drinkup.Registry, {name, JetstreamTasks}}}},
          {Drinkup.Jetstream.Socket, options}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      @doc """
      Returns a child spec for adding this consumer to a supervision tree.

      Runtime options override compile-time options.
      """
      def child_spec(runtime_opts) when is_list(runtime_opts) do
        opts = build_options(runtime_opts)

        %{
          id: opts.name,
          start: {__MODULE__, :start_link, [runtime_opts]},
          type: :supervisor,
          restart: :permanent,
          shutdown: 500
        }
      end

      def child_spec(_opts) do
        raise ArgumentError, "child_spec expects a keyword list of options"
      end

      defoverridable child_spec: 1

      # Build Options struct from compile-time and runtime options
      defp build_options(runtime_opts) do
        compile_opts = [
          name: @name || __MODULE__,
          host: @host,
          wanted_collections: @wanted_collections,
          wanted_dids: @wanted_dids,
          cursor: @cursor,
          require_hello: @require_hello,
          max_message_size_bytes: @max_message_size_bytes
        ]

        merged =
          compile_opts
          |> Keyword.merge(runtime_opts)
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()
          |> Map.put(:consumer, __MODULE__)

        Options.from(merged)
      end

      defp via_tuple(name) do
        {:via, Registry, {Drinkup.Registry, {name, JetstreamSupervisor}}}
      end
    end
  end

  # Options Update API

  @typedoc """
  Options that can be updated dynamically via `update_options/2`.

  - `:wanted_collections` - List of collection NSIDs or prefixes (max 100)
  - `:wanted_dids` - List of DIDs to filter (max 10,000)
  - `:max_message_size_bytes` - Maximum message size to receive

  Empty arrays will disable the corresponding filter (i.e., receive all).
  """
  @type update_opts :: %{
          optional(:wanted_collections) => [String.t()],
          optional(:wanted_dids) => [String.t()],
          optional(:max_message_size_bytes) => integer()
        }

  @doc """
  Update filters and options for an active Jetstream connection.

  Sends an options update message to the Jetstream server over the websocket
  connection. This allows you to dynamically change which collections and DIDs
  you're interested in without reconnecting.

  ## Parameters

  - `name` - The name of the Jetstream consumer (the `:name` option passed to `use Drinkup.Jetstream`)
  - `opts` - Map with optional fields:
    - `:wanted_collections` - List of collection NSIDs or prefixes (max 100)
    - `:wanted_dids` - List of DIDs to filter (max 10,000)
    - `:max_message_size_bytes` - Maximum message size to receive

  ## Examples

      # Filter to only posts
      Drinkup.Jetstream.update_options(:my_jetstream, %{
        wanted_collections: ["app.bsky.feed.post"]
      })

      # Filter to specific DIDs
      Drinkup.Jetstream.update_options(:my_jetstream, %{
        wanted_dids: ["did:plc:abc123", "did:plc:def456"]
      })

      # Disable all filters (receive all events)
      Drinkup.Jetstream.update_options(:my_jetstream, %{
        wanted_collections: [],
        wanted_dids: []
      })

  ## Return Value

  Returns `:ok` if the message was sent successfully, or `{:error, reason}` if
  the socket process could not be found or the message could not be sent.

  Note: The server may reject invalid updates (e.g., too many collections/DIDs).
  Invalid updates will result in the connection being closed by the server.
  """
  @spec update_options(atom(), update_opts()) :: :ok | {:error, term()}
  def update_options(name, opts) when is_atom(name) and is_map(opts) do
    case find_connection(name) do
      {:ok, {conn, stream}} ->
        message = build_options_update_message(opts)
        :ok = :gun.ws_send(conn, stream, {:text, message})

        Logger.debug("[Drinkup.Jetstream] Sent options update")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec find_connection(atom()) :: {:ok, {pid(), :gun.stream_ref()}} | {:error, :not_connected}
  defp find_connection(name) do
    # Look up the connection details from Registry
    case Registry.lookup(Drinkup.Registry, {name, JetstreamConnection}) do
      [{_socket_pid, {conn, stream}}] ->
        {:ok, {conn, stream}}

      [] ->
        {:error, :not_connected}
    end
  end

  @spec build_options_update_message(update_opts()) :: String.t()
  defp build_options_update_message(opts) do
    payload =
      %{}
      |> maybe_add_wanted_collections(Map.get(opts, :wanted_collections))
      |> maybe_add_wanted_dids(Map.get(opts, :wanted_dids))
      |> maybe_add_max_message_size(Map.get(opts, :max_message_size_bytes))

    message = %{
      "type" => "options_update",
      "payload" => payload
    }

    Jason.encode!(message)
  end

  @spec maybe_add_wanted_collections(map(), [String.t()] | nil) :: map()
  defp maybe_add_wanted_collections(payload, nil), do: payload

  defp maybe_add_wanted_collections(payload, collections) when is_list(collections) do
    Map.put(payload, "wantedCollections", collections)
  end

  @spec maybe_add_wanted_dids(map(), [String.t()] | nil) :: map()
  defp maybe_add_wanted_dids(payload, nil), do: payload

  defp maybe_add_wanted_dids(payload, dids) when is_list(dids) do
    Map.put(payload, "wantedDids", dids)
  end

  @spec maybe_add_max_message_size(map(), integer() | nil) :: map()
  defp maybe_add_max_message_size(payload, nil), do: payload

  defp maybe_add_max_message_size(payload, max_size) when is_integer(max_size) do
    Map.put(payload, "maxMessageSizeBytes", max_size)
  end
end
