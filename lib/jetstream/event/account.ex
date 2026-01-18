defmodule Drinkup.Jetstream.Event.Account do
  @moduledoc """
  Struct for account events from Jetstream.

  Represents a change to an account's status on a host (e.g., PDS or Relay).
  The semantics of this event are that the status is at the host which emitted
  the event, not necessarily that at the currently active PDS.

  For example, a Relay takedown would emit a takedown with `active: false`,
  even if the PDS is still active.
  """

  use TypedStruct

  typedstruct enforce: true do
    @typedoc """
    The status of an inactive account.

    Known values from the ATProto lexicon:
    - `:takendown` - Account has been taken down
    - `:suspended` - Account is suspended
    - `:deleted` - Account has been deleted
    - `:deactivated` - Account has been deactivated by the user
    - `:desynchronized` - Account is out of sync
    - `:throttled` - Account is throttled

    The status can also be any other string value for future compatibility.
    """
    @type status() ::
            :takendown
            | :suspended
            | :deleted
            | :deactivated
            | :desynchronized
            | :throttled
            | String.t()

    field :did, String.t()
    field :time_us, integer()
    field :kind, :account, default: :account
    field :active, boolean()
    field :seq, integer()
    field :time, NaiveDateTime.t()
    field :status, status() | nil
  end

  @doc """
  Parses a Jetstream account payload into an Account struct.

  ## Example Payload (Active)

      %{
        "active" => true,
        "did" => "did:plc:ufbl4k27gp6kzas5glhz7fim",
        "seq" => 1409753013,
        "time" => "2024-09-05T06:11:04.870Z"
      }

  ## Example Payload (Inactive)

      %{
        "active" => false,
        "did" => "did:plc:abc123",
        "seq" => 1409753014,
        "time" => "2024-09-05T06:12:00.000Z",
        "status" => "takendown"
      }
  """
  @spec from(String.t(), integer(), map()) :: t()
  def from(
        did,
        time_us,
        %{
          "active" => active,
          "seq" => seq,
          "time" => time
        } = account
      ) do
    %__MODULE__{
      did: did,
      time_us: time_us,
      active: active,
      seq: seq,
      time: parse_datetime(time),
      status: parse_status(Map.get(account, "status"))
    }
  end

  @spec parse_datetime(String.t()) :: NaiveDateTime.t()
  defp parse_datetime(time_str) do
    case NaiveDateTime.from_iso8601(time_str) do
      {:ok, datetime} -> datetime
      {:error, _} -> raise "Invalid datetime format: #{time_str}"
    end
  end

  @spec parse_status(String.t() | nil) :: status() | nil
  defp parse_status(nil), do: nil
  defp parse_status("takendown"), do: :takendown
  defp parse_status("suspended"), do: :suspended
  defp parse_status("deleted"), do: :deleted
  defp parse_status("deactivated"), do: :deactivated
  defp parse_status("desynchronized"), do: :desynchronized
  defp parse_status("throttled"), do: :throttled
  defp parse_status(status) when is_binary(status), do: status
end
