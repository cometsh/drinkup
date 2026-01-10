defmodule Drinkup.Tap.Event.Identity do
  @moduledoc """
  Struct for identity events from Tap.

  Represents handle or status changes for a DID.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :id, integer()
    field :did, String.t()
    field :handle, String.t() | nil
    field :is_active, boolean()
    field :status, String.t()
  end

  @spec from(map()) :: t()
  def from(%{
        "id" => id,
        "type" => "identity",
        "identity" =>
          %{
            "did" => did,
            "is_active" => is_active,
            "status" => status
          } = identity_data
      }) do
    handle = Map.get(identity_data, "handle")

    %__MODULE__{
      id: id,
      did: did,
      handle: handle,
      is_active: is_active,
      status: status
    }
  end
end
