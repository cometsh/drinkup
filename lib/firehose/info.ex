defmodule Drinkup.Firehose.Info do
  @moduledoc """
  Struct for info events from the ATProto Firehose.
  """

  use TypedStruct

  typedstruct enforce: true do
    field :name, String.t()
    field :message, String.t() | nil
  end

  @spec from(map()) :: t()
  def from(%{"name" => name} = msg) do
    message = Map.get(msg, "message")

    %__MODULE__{
      name: name,
      message: message
    }
  end
end
