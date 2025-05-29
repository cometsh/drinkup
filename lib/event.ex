defmodule Drinkup.Event do
  alias Drinkup.Event

  @spec from(String.t(), map()) ::
          Event.Commit.t()
          | Event.Sync.t()
          | Event.Identity.t()
          | Event.Account.t()
          | Event.Info.t()
          | nil
  def from("#commit", payload), do: Event.Commit.from(payload)
  def from("#sync", payload), do: Event.Sync.from(payload)
  def from("#identity", payload), do: Event.Identity.from(payload)
  def from("#account", payload), do: Event.Account.from(payload)
  def from("#info", payload), do: Event.Info.from(payload)
  def from(_type, _payload), do: nil

  @spec valid_seq?(integer() | nil, any()) :: boolean()
  def valid_seq?(nil, seq) when is_integer(seq), do: true
  def valid_seq?(last_seq, seq) when is_integer(last_seq) and is_integer(seq), do: seq > last_seq
  def valid_seq?(_last_seq, _seq), do: false
end
