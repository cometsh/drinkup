defmodule Drinkup do
  use Supervisor

  @type options() :: %{
          required(:consumer) => module(),
          optional(:host) => String.t(),
          optional(:cursor) => pos_integer()
        }

  @spec start_link(options()) :: Supervisor.on_start()
  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  def init(options) do
    children = [
      {Task.Supervisor, name: Drinkup.TaskSupervisor},
      {Drinkup.Socket, options}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
