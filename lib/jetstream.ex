defmodule Drinkup.Jetstream do
  @moduledoc """
  Supervisor for Jetstream event stream connections.

  Jetstream is a simplified JSON event stream that converts the CBOR-encoded
  ATProto Firehose into lightweight, friendly JSON events. It provides zstd
  compression and filtering capabilities for collections and DIDs.

  ## Usage

  Add Jetstream to your supervision tree:

      children = [
        {Drinkup.Jetstream, %{
          consumer: MyJetstreamConsumer,
          name: MyJetstream,
          wanted_collections: ["app.bsky.feed.post", "app.bsky.feed.like"]
        }}
      ]

  ## Configuration

  See `Drinkup.Jetstream.Options` for all available configuration options.

  ## Dynamic Filter Updates

  You can update filters after the connection is established:

      Drinkup.Jetstream.update_options(MyJetstream, %{
        wanted_collections: ["app.bsky.graph.follow"],
        wanted_dids: ["did:plc:abc123"]
      })

  ## Public Instances

  By default Drinkup connects to `jetstream2.us-east.bsky.network`.

  Bluesky operates a few different Jetstream instances:
  - `jetstream1.us-east.bsky.network`
  - `jetstream2.us-east.bsky.network`
  - `jetstream1.us-west.bsky.network`
  - `jetstream2.us-west.bsky.network`

  There also some third-party instances not run by Bluesky PBC:
  - `jetstream.fire.hose.cam`
  - `jetstream2.fr.hose.cam`
  - `jetstream1.us-east.fire.hose.cam`
  """

  use Supervisor
  require Logger
  alias Drinkup.Jetstream.Options

  @dialyzer nowarn_function: {:init, 1}

  @impl true
  def init({%Options{name: name} = drinkup_options, supervisor_options}) do
    children = [
      {Task.Supervisor, name: {:via, Registry, {Drinkup.Registry, {name, JetstreamTasks}}}},
      {Drinkup.Jetstream.Socket, drinkup_options}
    ]

    Supervisor.start_link(
      children,
      supervisor_options ++
        [name: {:via, Registry, {Drinkup.Registry, {name, JetstreamSupervisor}}}]
    )
  end

  @spec child_spec(Options.options()) :: Supervisor.child_spec()
  def child_spec(%{} = options), do: child_spec({options, [strategy: :one_for_one]})

  @spec child_spec({Options.options(), Keyword.t()}) :: Supervisor.child_spec()
  def child_spec({drinkup_options, supervisor_options}) do
    %{
      id: Map.get(drinkup_options, :name, __MODULE__),
      start: {__MODULE__, :init, [{Options.from(drinkup_options), supervisor_options}]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 500
    }
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

  - `name` - The name of the Jetstream instance (default: `Drinkup.Jetstream`)
  - `opts` - Map with optional fields:
    - `:wanted_collections` - List of collection NSIDs or prefixes (max 100)
    - `:wanted_dids` - List of DIDs to filter (max 10,000)
    - `:max_message_size_bytes` - Maximum message size to receive

  ## Examples

      # Filter to only posts
      Drinkup.Jetstream.update_options(MyJetstream, %{
        wanted_collections: ["app.bsky.feed.post"]
      })

      # Filter to specific DIDs
      Drinkup.Jetstream.update_options(MyJetstream, %{
        wanted_dids: ["did:plc:abc123", "did:plc:def456"]
      })

      # Disable all filters (receive all events)
      Drinkup.Jetstream.update_options(MyJetstream, %{
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
  def update_options(name \\ Drinkup.Jetstream, opts) when is_map(opts) do
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

  # Private functions

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
