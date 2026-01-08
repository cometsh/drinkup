defmodule Drinkup.Firehose do
  use Supervisor
  alias Drinkup.Firehose.Options

  @dialyzer nowarn_function: {:init, 1}
  @impl true
  def init({%Options{name: name} = drinkup_options, supervisor_options}) do
    children = [
      {Task.Supervisor, name: {:via, Registry, {Drinkup.Registry, {name, Tasks}}}},
      {Drinkup.Firehose.Socket, drinkup_options}
    ]

    Supervisor.start_link(
      children,
      supervisor_options ++ [name: {:via, Registry, {Drinkup.Registry, {name, Supervisor}}}]
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
end
