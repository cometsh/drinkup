defmodule Drinkup.Options do
  use TypedStruct

  @default_host "https://bsky.network"

  @type options() :: %{
          required(:consumer) => module(),
          optional(:name) => atom(),
          optional(:host) => String.t(),
          optional(:cursor) => pos_integer()
        }

  typedstruct do
    field :consumer, module(), enforce: true
    field :name, atom(), default: Drinkup
    field :host, String.t(), default: @default_host
    field :cursor, pos_integer() | nil
  end

  @spec from(options()) :: t()
  def from(%{consumer: _} = options), do: struct(__MODULE__, options)
end
