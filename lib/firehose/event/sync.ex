defmodule Drinkup.Firehose.Event.Sync do
  @moduledoc """
  Struct for sync events from the ATProto Firehose.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :seq, integer()
    field :did, String.t()
    field :blocks, binary()
    field :rev, String.t()
    field :time, NaiveDateTime.t()
  end

  @spec from(map()) :: t()
  def from(%{"seq" => seq, "did" => did, "blocks" => blocks, "rev" => rev, "time" => time}) do
    time = NaiveDateTime.from_iso8601!(time)

    %__MODULE__{
      seq: seq,
      did: did,
      blocks: blocks,
      rev: rev,
      time: time
    }
  end
end
