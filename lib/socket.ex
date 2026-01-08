defmodule Drinkup.Socket do
  # TODO: talk about how to implment, but that it's for internal use
  @moduledoc false

  require Logger

  @behaviour :gen_statem

  @type frame ::
          {:binary, binary()}
          | {:text, String.t()}
          | :close
          | {:close, errno :: integer(), reason :: binary()}

  @type user_data :: term()

  @type reconnect_strategy ::
          :exponential
          | {:exponential, max_backoff :: pos_integer()}
          | {:custom, (attempt :: pos_integer() -> delay_ms :: pos_integer())}

  @type option ::
          {:host, String.t()}
          | {:flow, pos_integer()}
          | {:timeout, pos_integer()}
          | {:tls_opts, keyword()}
          | {:gun_opts, map()}
          | {:reconnect_strategy, reconnect_strategy()}
          | {atom(), term()}

  @callback init(opts :: keyword()) :: {:ok, user_data()} | {:error, reason :: term()}

  @callback build_path(data :: user_data()) :: String.t()

  @callback handle_frame(frame :: frame(), data :: user_data()) ::
              {:ok, new_data :: user_data()} | :noop | nil | {:error, reason :: term()}

  @callback handle_connected(data :: user_data()) :: {:ok, new_data :: user_data()}

  @callback handle_disconnected(reason :: term(), data :: user_data()) ::
              {:ok, new_data :: user_data()}

  @optional_callbacks handle_connected: 1, handle_disconnected: 2

  defstruct [
    :module,
    :user_data,
    :options,
    :conn,
    :stream,
    reconnect_attempts: 0
  ]

  defmacro __using__(_opts) do
    quote do
      @behaviour Drinkup.Socket

      def start_link(opts, statem_opts \\ [])

      def start_link(opts, statem_opts) do
        Drinkup.Socket.start_link(__MODULE__, opts, statem_opts)
      end

      defoverridable start_link: 2

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts, []]},
          type: :worker,
          restart: :permanent,
          shutdown: 500
        }
      end

      defoverridable child_spec: 1

      @impl true
      def handle_connected(data), do: {:ok, data}

      @impl true
      def handle_disconnected(_reason, data), do: {:ok, data}

      defoverridable handle_connected: 1, handle_disconnected: 2
    end
  end

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  @doc """
  Start a WebSocket connection process.

  ## Parameters

    * `module` - The module implementing the Drinkup.Socket behaviour
    * `opts` - Keyword list of options (see module documentation)
    * `statem_opts` - Options passed to `:gen_statem.start_link/3`
  """
  def start_link(module, opts, statem_opts) do
    :gen_statem.start_link(__MODULE__, {module, opts}, statem_opts)
  end

  @impl true
  def init({module, opts}) do
    case module.init(opts) do
      {:ok, user_data} ->
        options = parse_options(opts)

        data = %__MODULE__{
          module: module,
          user_data: user_data,
          options: options,
          reconnect_attempts: 0
        }

        {:ok, :disconnected, data, [{:next_event, :internal, :connect}]}

      {:error, reason} ->
        {:stop, {:init_failed, reason}}
    end
  end

  # :disconnected state - waiting to connect or reconnect

  def disconnected(:enter, _from, _data) do
    Logger.debug("[Drinkup.Socket] Entering disconnected state")
    :keep_state_and_data
  end

  def disconnected(:internal, :connect, data) do
    {:next_state, :connecting_http, data}
  end

  def disconnected(:timeout, :reconnect, data) do
    {:next_state, :connecting_http, data}
  end

  # :connecting_http state - establishing HTTP connection with TLS

  def connecting_http(:enter, _from, %{options: options} = data) do
    Logger.debug("[Drinkup.Socket] Connecting to HTTP")

    %{host: host, port: port} = URI.new!(options.host)

    gun_opts =
      Map.merge(
        %{
          retry: 0,
          protocols: [:http],
          connect_timeout: options.timeout,
          domain_lookup_timeout: options.timeout,
          tls_handshake_timeout: options.timeout,
          tls_opts: options.tls_opts
        },
        options.gun_opts
      )

    case :gun.open(:binary.bin_to_list(host), port, gun_opts) do
      {:ok, conn} ->
        {:keep_state, %{data | conn: conn}, [{:state_timeout, options.timeout, :connect_timeout}]}

      {:error, reason} ->
        Logger.error("[Drinkup.Socket] Failed to open connection: #{inspect(reason)}")
        {:stop, {:connect_failed, reason}}
    end
  end

  def connecting_http(:info, {:gun_up, _conn, :http}, data) do
    {:next_state, :connecting_ws, data}
  end

  def connecting_http(:state_timeout, :connect_timeout, data) do
    Logger.error("[Drinkup.Socket] HTTP connection timeout")
    trigger_reconnect(data)
  end

  # :connecting_ws state - upgrading to WebSocket

  def connecting_ws(
        :enter,
        _from,
        %{module: module, user_data: user_data, options: options} = data
      ) do
    Logger.debug("[Drinkup.Socket] Upgrading connection to WebSocket")

    path = module.build_path(user_data)
    stream = :gun.ws_upgrade(data.conn, path, [], %{flow: options.flow})

    {:keep_state, %{data | stream: stream}, [{:state_timeout, options.timeout, :upgrade_timeout}]}
  end

  def connecting_ws(:info, {:gun_upgrade, _conn, _stream, ["websocket"], _headers}, data) do
    {:next_state, :connected, data}
  end

  def connecting_ws(:info, {:gun_response, _conn, _stream, _fin, status, _headers}, data) do
    Logger.error("[Drinkup.Socket] WebSocket upgrade failed with status: #{status}")
    trigger_reconnect(data)
  end

  def connecting_ws(:info, {:gun_error, _conn, _stream, reason}, data) do
    Logger.error("[Drinkup.Socket] WebSocket upgrade error: #{inspect(reason)}")
    trigger_reconnect(data)
  end

  def connecting_ws(:state_timeout, :upgrade_timeout, data) do
    Logger.error("[Drinkup.Socket] WebSocket upgrade timeout")
    trigger_reconnect(data)
  end

  # :connected state - active WebSocket connection

  def connected(:enter, _from, %{module: module, user_data: user_data} = data) do
    Logger.debug("[Drinkup.Socket] WebSocket connected")

    case module.handle_connected(user_data) do
      {:ok, new_user_data} ->
        {:keep_state, %{data | user_data: new_user_data, reconnect_attempts: 0}}

      _ ->
        {:keep_state, %{data | reconnect_attempts: 0}}
    end
  end

  def connected(
        :info,
        {:gun_ws, conn, _stream, frame},
        %{module: module, user_data: user_data, options: options} = data
      ) do
    result = module.handle_frame(frame, user_data)

    :ok = :gun.update_flow(conn, frame, options.flow)

    case result do
      {:ok, new_user_data} ->
        {:keep_state, %{data | user_data: new_user_data}}

      result when result in [:noop, nil] ->
        :keep_state_and_data

      {:error, reason} ->
        Logger.error("[Drinkup.Socket] Frame handler error: #{inspect(reason)}")
        :keep_state_and_data
    end
  end

  def connected(:info, {:gun_ws, _conn, _stream, :close}, data) do
    Logger.info("[Drinkup.Socket] WebSocket closed by remote")
    trigger_reconnect(data, :remote_close)
  end

  def connected(:info, {:gun_ws, _conn, _stream, {:close, errno, reason}}, data) do
    Logger.info("[Drinkup.Socket] WebSocket closed: #{errno} - #{inspect(reason)}")
    trigger_reconnect(data, {:remote_close, errno, reason})
  end

  def connected(:info, {:gun_down, old_conn, _proto, _reason, _killed_streams}, %{conn: new_conn})
      when old_conn != new_conn do
    Logger.debug("[Drinkup.Socket] Ignoring :gun_down for old connection")
    :keep_state_and_data
  end

  def connected(:info, {:gun_down, _conn, _proto, reason, _killed_streams}, data) do
    Logger.info("[Drinkup.Socket] Connection down: #{inspect(reason)}")
    trigger_reconnect(data, {:connection_down, reason})
  end

  def connected(
        :internal,
        :reconnect,
        %{conn: conn, options: options, reconnect_attempts: attempts} = data
      ) do
    :ok = :gun.close(conn)
    :ok = :gun.flush(conn)

    backoff = calculate_backoff(attempts, options.reconnect_strategy)

    Logger.info("[Drinkup.Socket] Reconnecting in #{backoff}ms (attempt #{attempts + 1})")

    {:next_state, :disconnected,
     %{data | conn: nil, stream: nil, reconnect_attempts: attempts + 1},
     [{{:timeout, :reconnect}, backoff, :reconnect}]}
  end

  # Helper functions

  defp trigger_reconnect(data, reason \\ :unknown) do
    %{module: module, user_data: user_data} = data

    case module.handle_disconnected(reason, user_data) do
      {:ok, new_user_data} ->
        {:keep_state, %{data | user_data: new_user_data}, [{:next_event, :internal, :reconnect}]}

      _ ->
        {:keep_state_and_data, [{:next_event, :internal, :reconnect}]}
    end
  end

  defp parse_options(opts) do
    %{
      host: Keyword.fetch!(opts, :host),
      flow: Keyword.get(opts, :flow, 10),
      timeout: Keyword.get(opts, :timeout, :timer.seconds(5)),
      tls_opts: Keyword.get(opts, :tls_opts, default_tls_opts()),
      gun_opts: Keyword.get(opts, :gun_opts, %{}),
      reconnect_strategy: Keyword.get(opts, :reconnect_strategy, :exponential)
    }
  end

  defp default_tls_opts do
    [
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp calculate_backoff(attempt, strategy) do
    case strategy do
      :exponential ->
        exponential_backoff(attempt, :timer.seconds(60))

      {:exponential, max_backoff} ->
        exponential_backoff(attempt, max_backoff)

      {:custom, func} when is_function(func, 1) ->
        func.(attempt)
    end
  end

  defp exponential_backoff(attempt, max_backoff) do
    base = :timer.seconds(1)
    delay = min(base * :math.pow(2, attempt), max_backoff)
    jitter = :rand.uniform(trunc(delay * 0.1))
    trunc(delay) + jitter
  end
end
