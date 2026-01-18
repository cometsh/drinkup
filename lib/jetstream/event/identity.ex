defmodule Drinkup.Jetstream.Event.Identity do
  @moduledoc """
  Struct for identity events from Jetstream.

  Represents a change to an account's identity, such as an updated handle,
  signing key, or PDS hosting endpoint. This serves as a signal to downstream
  services to refresh their identity cache.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :did, String.t()
    field :time_us, integer()
    field :kind, :identity, default: :identity
    field :handle, String.t() | nil
    field :seq, integer()
    field :time, NaiveDateTime.t()
  end

  @doc """
  Parses a Jetstream identity payload into an Identity struct.

  ## Example Payload

      %{
        "did" => "did:plc:ufbl4k27gp6kzas5glhz7fim",
        "handle" => "yohenrique.bsky.social",
        "seq" => 1409752997,
        "time" => "2024-09-05T06:11:04.870Z"
      }
  """
  @spec from(String.t(), integer(), map()) :: t()
  def from(
        did,
        time_us,
        %{
          "seq" => seq,
          "time" => time
        } = identity
      ) do
    %__MODULE__{
      did: did,
      time_us: time_us,
      handle: Map.get(identity, "handle"),
      seq: seq,
      time: parse_datetime(time)
    }
  end

  @spec parse_datetime(String.t()) :: NaiveDateTime.t()
  defp parse_datetime(time_str) do
    case NaiveDateTime.from_iso8601(time_str) do
      {:ok, datetime} -> datetime
      {:error, _} -> raise "Invalid datetime format: #{time_str}"
    end
  end
end
