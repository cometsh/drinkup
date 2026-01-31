defmodule Drinkup.Tap do
  @moduledoc """
  Module for handling events from a
  [Tap](https://github.com/bluesky-social/indigo/tree/main/cmd/tap) instance.

  Tap is a complete sync and backfill solution which handles the firehose
  connection itself, and automatically searches for repositories to backfill
  from based on the options given to it. It's great for building an app that
  wants all of a certain set of records within the AT Protocol network.

  This module requires you to be running a properly configured Tap instance, it
  doesn't spawn one for itself.

  ## Usage

      defmodule MyTapConsumer do
        use Drinkup.Tap,
          name: :my_tap,
          host: "http://localhost:2480",
          admin_password: System.get_env("TAP_PASSWORD")

        @impl true
        def handle_event(event) do
          # Process event
          :ok
        end
      end

      # In your application supervision tree:
      children = [MyTapConsumer]

  You can also interact with the Tap HTTP API to manually start tracking
  specific repositories or get information about what's going on.

      # Add repos to track (triggers backfill)
      Drinkup.Tap.add_repos(:my_tap, ["did:plc:abc123"])

      # Get stats
      {:ok, count} = Drinkup.Tap.get_repo_count(:my_tap)
  """

  alias Drinkup.Tap.Options

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use Supervisor
      @behaviour Drinkup.Tap.Consumer

      alias Drinkup.Tap.Options

      # Store compile-time options as module attributes
      @name Keyword.get(opts, :name)
      @host Keyword.get(opts, :host, "http://localhost:2480")
      @admin_password Keyword.get(opts, :admin_password)
      @disable_acks Keyword.get(opts, :disable_acks, false)

      @doc """
      Starts the Tap consumer supervisor.

      Accepts optional runtime configuration that overrides compile-time options.
      """
      def start_link(runtime_opts \\ []) do
        opts = build_options(runtime_opts)
        Supervisor.start_link(__MODULE__, opts, name: via_tuple(opts.name))
      end

      @impl true
      def init(%Options{name: name} = options) do
        # Register options in Registry for HTTP API access
        Registry.register(Drinkup.Registry, {name, TapOptions}, options)

        children = [
          {Task.Supervisor, name: {:via, Registry, {Drinkup.Registry, {name, TapTasks}}}},
          {Drinkup.Tap.Socket, options}
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
          admin_password: @admin_password,
          disable_acks: @disable_acks
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
        {:via, Registry, {Drinkup.Registry, {name, TapSupervisor}}}
      end
    end
  end

  # HTTP API Functions

  @doc """
  Add DIDs to track.

  Triggers backfill for the specified DIDs. Historical events will be fetched
  from each repo's PDS, followed by live events from the firehose.

  ## Parameters

  - `name` - The name of the Tap consumer (the `:name` option passed to `use Drinkup.Tap`)
  - `dids` - List of DID strings to add
  """
  @spec add_repos(atom(), [String.t()]) :: {:ok, term()} | {:error, term()}
  def add_repos(name, dids) when is_atom(name) and is_list(dids) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :post, "/repos/add", %{dids: dids}) do
      {:ok, response}
    end
  end

  @doc """
  Remove DIDs from tracking.

  Stops syncing the specified repos and deletes tracked repo metadata. Does not
  delete buffered events in the outbox.

  ## Parameters

  - `name` - The name of the Tap consumer (the `:name` option passed to `use Drinkup.Tap`)
  - `dids` - List of DID strings to remove
  """
  @spec remove_repos(atom(), [String.t()]) :: {:ok, term()} | {:error, term()}
  def remove_repos(name, dids) when is_atom(name) and is_list(dids) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :post, "/repos/remove", %{dids: dids}) do
      {:ok, response}
    end
  end

  @doc """
  Resolve a DID to its DID document.

  ## Parameters

  - `name` - The name of the Tap consumer
  - `did` - DID string to resolve
  """
  @spec resolve_did(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def resolve_did(name, did) when is_atom(name) and is_binary(did) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/resolve/#{did}") do
      {:ok, response}
    end
  end

  @doc """
  Get info about a tracked repo.

  Returns repo state, repo rev, record count, error info, and retry count.

  ## Parameters

  - `name` - The name of the Tap consumer
  - `did` - DID string to get info for
  """
  @spec get_repo_info(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def get_repo_info(name, did) when is_atom(name) and is_binary(did) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/info/#{did}") do
      {:ok, response}
    end
  end

  @doc """
  Get the total number of tracked repos.

  ## Parameters

  - `name` - The name of the Tap consumer
  """
  @spec get_repo_count(atom()) :: {:ok, integer()} | {:error, term()}
  def get_repo_count(name) when is_atom(name) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/repo-count") do
      {:ok, response}
    end
  end

  @doc """
  Get the total number of tracked records.

  ## Parameters

  - `name` - The name of the Tap consumer
  """
  @spec get_record_count(atom()) :: {:ok, integer()} | {:error, term()}
  def get_record_count(name) when is_atom(name) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/record-count") do
      {:ok, response}
    end
  end

  @doc """
  Get the number of events in the outbox buffer.

  ## Parameters

  - `name` - The name of the Tap consumer
  """
  @spec get_outbox_buffer(atom()) :: {:ok, integer()} | {:error, term()}
  def get_outbox_buffer(name) when is_atom(name) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/outbox-buffer") do
      {:ok, response}
    end
  end

  @doc """
  Get the number of events in the resync buffer.

  ## Parameters

  - `name` - The name of the Tap consumer
  """
  @spec get_resync_buffer(atom()) :: {:ok, integer()} | {:error, term()}
  def get_resync_buffer(name) when is_atom(name) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/resync-buffer") do
      {:ok, response}
    end
  end

  @doc """
  Get current firehose and list repos cursors.

  ## Parameters

  - `name` - The name of the Tap consumer
  """
  @spec get_cursors(atom()) :: {:ok, map()} | {:error, term()}
  def get_cursors(name) when is_atom(name) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/cursors") do
      {:ok, response}
    end
  end

  @doc """
  Check Tap health status.

  Returns `{:ok, %{"status" => "ok"}}` if healthy.

  ## Parameters

  - `name` - The name of the Tap consumer
  """
  @spec health(atom()) :: {:ok, map()} | {:error, term()}
  def health(name) when is_atom(name) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/health") do
      {:ok, response}
    end
  end

  @spec get_options(atom()) :: {:ok, Options.t()} | {:error, :not_found}
  defp get_options(name) do
    case Registry.lookup(Drinkup.Registry, {name, TapOptions}) do
      [{_pid, options}] -> {:ok, options}
      [] -> {:error, :not_found}
    end
  end

  @spec make_request(Options.t(), atom(), String.t(), map() | nil) ::
          {:ok, term()} | {:error, term()}
  defp make_request(options, method, path, body \\ nil) do
    url = build_url(options.host, path)
    headers = build_headers(options.admin_password)

    request_opts = [
      method: method,
      url: url,
      headers: headers
    ]

    request_opts =
      if body do
        Keyword.merge(request_opts, json: body)
      else
        request_opts
      end

    case Req.request(request_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_url(String.t(), String.t()) :: String.t()
  defp build_url(host, path) do
    host = String.trim_trailing(host, "/")
    "#{host}#{path}"
  end

  @spec build_headers(String.t() | nil) :: list()
  defp build_headers(nil), do: []

  defp build_headers(admin_password) do
    credentials = "admin:#{admin_password}"
    auth_header = "Basic #{Base.encode64(credentials)}"
    [{"authorization", auth_header}]
  end
end
