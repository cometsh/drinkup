defmodule Drinkup.Event.Identity do
  @moduledoc """
  Struct for identity events from the ATProto Firehose.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :seq, integer()
    field :did, String.t()
    field :time, NaiveDateTime.t()
    field :handle, String.t() | nil
  end

  @spec from(map()) :: t()
  def from(%{"seq" => seq, "did" => did, "time" => time} = msg) do
    handle = Map.get(msg, "handle")
    time = NaiveDateTime.from_iso8601!(time)

    %__MODULE__{
      seq: seq,
      did: did,
      time: time,
      handle: handle
    }
  end
end
