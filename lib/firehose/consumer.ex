defmodule Drinkup.Firehose.Consumer do
  @moduledoc """
  Behaviour for handling Firehose events.

  Implemented by `Drinkup.Firehose`, you'll likely want to be using that instead.
  """

  @callback handle_event(Drinkup.Firehose.Event.t()) :: any()
end
