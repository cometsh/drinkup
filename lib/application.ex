defmodule Drinkup.Application do
  use Application

  def start(_type, _args) do
    children = [{Registry, keys: :unique, name: Drinkup.Registry}]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
