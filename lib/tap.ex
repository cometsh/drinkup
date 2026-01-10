defmodule Drinkup.Tap do
  @moduledoc """
  Supervisor and HTTP API for Tap indexer/backfill service.

  Tap simplifies AT sync by handling the firehose connection, verification,
  backfill, and filtering. Your application connects to a Tap service and
  receives simple JSON events for only the repos and collections you care about.

  ## Usage

  Add Tap to your supervision tree:

      children = [
        {Drinkup.Tap, %{
          consumer: MyTapConsumer,
          name: MyTap,
          host: "http://localhost:2480",
          admin_password: "secret"  # optional
        }}
      ]

  Then interact with the Tap HTTP API:

      # Add repos to track (triggers backfill)
      Drinkup.Tap.add_repos(MyTap, ["did:plc:abc123"])

      # Get stats
      {:ok, count} = Drinkup.Tap.get_repo_count(MyTap)

  ## Configuration

  Tap itself is configured via environment variables. See the Tap documentation
  for details on configuring collection filters, signal collections, and other
  operational settings:
  https://github.com/bluesky-social/indigo/blob/main/cmd/tap/README.md
  """

  use Supervisor
  alias Drinkup.Tap.Options

  @dialyzer nowarn_function: {:init, 1}
  @impl true
  def init({%Options{name: name} = drinkup_options, supervisor_options}) do
    # Register options in Registry for HTTP API access
    Registry.register(Drinkup.Registry, {name, TapOptions}, drinkup_options)

    children = [
      {Task.Supervisor, name: {:via, Registry, {Drinkup.Registry, {name, TapTasks}}}},
      {Drinkup.Tap.Socket, drinkup_options}
    ]

    Supervisor.start_link(
      children,
      supervisor_options ++ [name: {:via, Registry, {Drinkup.Registry, {name, TapSupervisor}}}]
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

  # HTTP API Functions

  @doc """
  Add DIDs to track.

  Triggers backfill for the specified DIDs. Historical events will be fetched
  from each repo's PDS, followed by live events from the firehose.
  """
  @spec add_repos(atom(), [String.t()]) :: {:ok, term()} | {:error, term()}
  def add_repos(name \\ Drinkup.Tap, dids) when is_list(dids) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :post, "/repos/add", %{dids: dids}) do
      {:ok, response}
    end
  end

  @doc """
  Remove DIDs from tracking.

  Stops syncing the specified repos and deletes tracked repo metadata. Does not
  delete buffered events in the outbox.
  """
  @spec remove_repos(atom(), [String.t()]) :: {:ok, term()} | {:error, term()}
  def remove_repos(name \\ Drinkup.Tap, dids) when is_list(dids) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :post, "/repos/remove", %{dids: dids}) do
      {:ok, response}
    end
  end

  @doc """
  Resolve a DID to its DID document.
  """
  @spec resolve_did(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def resolve_did(name \\ Drinkup.Tap, did) when is_binary(did) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/resolve/#{did}") do
      {:ok, response}
    end
  end

  @doc """
  Get info about a tracked repo.

  Returns repo state, repo rev, record count, error info, and retry count.
  """
  @spec get_repo_info(atom(), String.t()) :: {:ok, term()} | {:error, term()}
  def get_repo_info(name \\ Drinkup.Tap, did) when is_binary(did) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/info/#{did}") do
      {:ok, response}
    end
  end

  @doc """
  Get the total number of tracked repos.
  """
  @spec get_repo_count(atom()) :: {:ok, integer()} | {:error, term()}
  def get_repo_count(name \\ Drinkup.Tap) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/repo-count") do
      {:ok, response}
    end
  end

  @doc """
  Get the total number of tracked records.
  """
  @spec get_record_count(atom()) :: {:ok, integer()} | {:error, term()}
  def get_record_count(name \\ Drinkup.Tap) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/record-count") do
      {:ok, response}
    end
  end

  @doc """
  Get the number of events in the outbox buffer.
  """
  @spec get_outbox_buffer(atom()) :: {:ok, integer()} | {:error, term()}
  def get_outbox_buffer(name \\ Drinkup.Tap) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/outbox-buffer") do
      {:ok, response}
    end
  end

  @doc """
  Get the number of events in the resync buffer.
  """
  @spec get_resync_buffer(atom()) :: {:ok, integer()} | {:error, term()}
  def get_resync_buffer(name \\ Drinkup.Tap) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/resync-buffer") do
      {:ok, response}
    end
  end

  @doc """
  Get current firehose and list repos cursors.
  """
  @spec get_cursors(atom()) :: {:ok, map()} | {:error, term()}
  def get_cursors(name \\ Drinkup.Tap) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/stats/cursors") do
      {:ok, response}
    end
  end

  @doc """
  Check Tap health status.

  Returns `{:ok, %{"status" => "ok"}}` if healthy.
  """
  @spec health(atom()) :: {:ok, map()} | {:error, term()}
  def health(name \\ Drinkup.Tap) do
    with {:ok, options} <- get_options(name),
         {:ok, response} <- make_request(options, :get, "/health") do
      {:ok, response}
    end
  end

  # Private Functions

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
