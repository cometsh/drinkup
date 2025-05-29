defmodule Drinkup.Consumer do
  @moduledoc """
  An unopinionated consumer of the Firehose. Will receive all events, not just commits.
  """

  alias Drinkup.{ConsumerGroup, Event}

  @callback handle_event(Event.t()) :: any()

  defmacro __using__(_opts) do
    quote location: :keep do
      use GenServer
      require Logger

      @behaviour Drinkup.Consumer

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :worker,
          restart: :permanent,
          max_restarts: 0,
          shutdown: 500
        }
      end

      def start_link(opts) do
        GenServer.start_link(__MODULE__, [], opts)
      end

      @impl GenServer
      def init(_) do
        ConsumerGroup.join()
        {:ok, nil}
      end

      @impl GenServer
      def handle_info({:event, event}, state) do
        {:ok, _pid} =
          Task.start(fn ->
            try do
              __MODULE__.handle_event(event)
            rescue
              e ->
                Logger.error(
                  "Error in event handler: #{Exception.format(:error, e, __STACKTRACE__)}"
                )
            end
          end)

        {:noreply, state}
      end

      defoverridable GenServer
    end
  end
end
