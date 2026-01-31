defmodule Drinkup.Firehose do
  @moduledoc """
  Module for handling events from the AT Protocol [firehose](https://docs.bsky.app/docs/advanced-guides/firehose).

  Due to the nature of the firehose, this will result in a lot of incoming
  traffic as it receives every repo and identity event within the network. If
  you're concerened about bandwidth constaints or just don't need a
  whole-network sync, you may be better off using `Drinkup.Jetstream` or
  `Drinkup.Tap`.

  ## Usage

      defmodule MyFirehoseConsumer do
        use Drinkup.Firehose,
          name: :my_firehose,
          host: "https://bsky.network",
          cursor: nil

        @impl true
        def handle_event(%Drinkup.Firehose.Event.Commit{} = event) do
          IO.inspect(event, label: "Commit")
          :ok
        end

        def handle_event(_event), do: :ok
      end

      # In your application supervision tree:
      children = [MyFirehoseConsumer]

  Exceptions raised by `handle_event/1` will be logged instead of killing and
  restarting the socket process.

  ## Options

  - `:name` - Unique name for this Firehose instance (default: the module name)
  - `:host` - Firehose relay URL (default: `"https://bsky.network"`)
  - `:cursor` - Optional sequence number to resume streaming from

  ## Runtime Configuration

  You can override options at runtime by providing them to `child_spec/1`:

      children = [
        {MyFirehoseConsumer, name: :runtime_name, cursor: 12345}
      ]

  ## Event Types

  `handle_event/1` will receive the following event structs:

  - `Drinkup.Firehose.Event.Commit` - Repository commits
  - `Drinkup.Firehose.Event.Sync` - Sync events
  - `Drinkup.Firehose.Event.Identity` - Identity updates
  - `Drinkup.Firehose.Event.Account` - Account status changes
  - `Drinkup.Firehose.Event.Info` - Info messages
  """

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use Supervisor
      @behaviour Drinkup.Firehose.Consumer

      alias Drinkup.Firehose.Options

      # Store compile-time options as module attributes
      @name Keyword.get(opts, :name)
      @host Keyword.get(opts, :host, "https://bsky.network")
      @cursor Keyword.get(opts, :cursor)

      @doc """
      Starts the Firehose consumer supervisor.

      Accepts optional runtime configuration that overrides compile-time options.
      """
      def start_link(runtime_opts \\ []) do
        # Merge compile-time and runtime options
        opts = build_options(runtime_opts)
        Supervisor.start_link(__MODULE__, opts, name: via_tuple(opts.name))
      end

      @impl true
      def init(%Options{name: name} = options) do
        children = [
          {Task.Supervisor, name: {:via, Registry, {Drinkup.Registry, {name, Tasks}}}},
          {Drinkup.Firehose.Socket, options}
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
        # Compile-time defaults
        compile_opts = [
          name: @name || __MODULE__,
          host: @host,
          cursor: @cursor
        ]

        # Merge with runtime opts (runtime takes precedence)
        merged =
          compile_opts
          |> Keyword.merge(runtime_opts)
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()
          |> Map.put(:consumer, __MODULE__)

        Options.from(merged)
      end

      defp via_tuple(name) do
        {:via, Registry, {Drinkup.Registry, {name, Supervisor}}}
      end
    end
  end
end
