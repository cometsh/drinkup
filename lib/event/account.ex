defmodule Drinkup.Event.Account do
  @moduledoc """
  Struct for account events from the ATProto Firehose.
  """

  use TypedStruct

  @type status() ::
          :takendown
          | :suspended
          | :deleted
          | :deactivated
          | :desynchronized
          | :throttled
          | String.t()

  typedstruct enforce: true do
    field :seq, integer()
    field :did, String.t()
    field :time, NaiveDateTime.t()
    field :active, bool()
    field :status, status(), enforce: false
  end

  @spec from(map()) :: t()
  def from(%{"seq" => seq, "did" => did, "time" => time, "active" => active} = msg) do
    status = recognise_status(Map.get(msg, "status"))
    time = NaiveDateTime.from_iso8601!(time)

    %__MODULE__{
      seq: seq,
      did: did,
      time: time,
      active: active,
      status: status
    }
  end

  @spec recognise_status(String.t()) :: status()
  defp recognise_status(status)
       when status in [
              "takendown",
              "suspended",
              "deleted",
              "deactivated",
              "desynchronized",
              "throttled"
            ],
       do: String.to_atom(status)

  defp recognise_status(status) when is_binary(status), do: status
  defp recognise_status(nil), do: nil
end
