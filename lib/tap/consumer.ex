defmodule Drinkup.Tap.Consumer do
  @moduledoc """
  Behaviour for handling Tap events.

  Implemented by `Drinkup.Tap`, you'll likely want to be using that instead.
  """

  alias Drinkup.Tap.Event

  @callback handle_event(Event.Record.t() | Event.Identity.t()) :: any()
end
