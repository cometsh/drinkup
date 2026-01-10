defmodule Drinkup.Tap.Event.Record do
  @moduledoc """
  Struct for record events from Tap.

  Represents create, update, or delete operations on records in the repository.
  """

  use TypedStruct

  typedstruct enforce: true do
    @type action() :: :create | :update | :delete

    field :id, integer()
    field :live, boolean()
    field :rev, String.t()
    field :did, String.t()
    field :collection, String.t()
    field :rkey, String.t()
    field :action, action()
    field :cid, String.t() | nil
    field :record, map() | nil
  end

  @spec from(map()) :: t()
  def from(%{
        "id" => id,
        "type" => "record",
        "record" =>
          %{
            "live" => live,
            "rev" => rev,
            "did" => did,
            "collection" => collection,
            "rkey" => rkey,
            "action" => action
          } = record_data
      }) do
    cid = Map.get(record_data, "cid")
    record = Map.get(record_data, "record")

    %__MODULE__{
      id: id,
      live: live,
      rev: rev,
      did: did,
      collection: collection,
      rkey: rkey,
      action: parse_action(action),
      cid: cid,
      record: record
    }
  end

  @spec parse_action(String.t()) :: action()
  defp parse_action("create"), do: :create
  defp parse_action("update"), do: :update
  defp parse_action("delete"), do: :delete
end
