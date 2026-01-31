defmodule Drinkup.Jetstream.Consumer do
  @moduledoc """
  Behaviour for handling Jetstream events.

  Implemented by `Drinkup.Jetstream`, you'll likely want to be using that instead.
  """

  alias Drinkup.Jetstream.Event

  @callback handle_event(Event.t()) :: any()
end
