defmodule Drinkup.ConsumerGroup do
  @moduledoc """
  Register consumers and dispatch events to them.
  """

  alias Drinkup.Event

  @scope __MODULE__
  @group :consumers

  def start_link(_) do
    :pg.start_link(@scope)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @spec join() :: :ok
  def join(), do: join(self())

  @spec join(pid()) :: :ok
  def join(pid), do: :pg.join(@scope, @group, pid)

  @spec dispatch(Event.t()) :: :ok
  def dispatch(event) do
    @scope
    |> :pg.get_members(@group)
    |> Enum.each(&send(&1, {:event, event}))
  end

  # TODO: read `:pg` docs on what `monitor` is used fo
end
