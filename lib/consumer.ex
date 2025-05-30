defmodule Drinkup.Consumer do
  @moduledoc """
  An unopinionated consumer of the Firehose. Will receive all events, not just commits.
  """

  alias Drinkup.Event

  @callback handle_event(Event.t()) :: any()
end
