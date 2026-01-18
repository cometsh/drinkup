defmodule Drinkup.Jetstream.Event.Commit do
  @moduledoc """
  Struct for commit events from Jetstream.

  Represents a repository commit containing either a create, update, or delete
  operation on a record. Unlike the Firehose commit events, Jetstream provides
  simplified JSON structures without CAR/CBOR encoding.
  """

  use TypedStruct

  typedstruct enforce: true do
    @typedoc """
    The operation type for this commit.

    - `:create` - A new record was created
    - `:update` - An existing record was updated
    - `:delete` - An existing record was deleted
    """
    @type operation() :: :create | :update | :delete

    field :did, String.t()
    field :time_us, integer()
    field :kind, :commit, default: :commit
    field :operation, operation()
    field :collection, String.t()
    field :rkey, String.t()
    field :rev, String.t()
    field :record, map() | nil
    field :cid, String.t() | nil
  end

  @doc """
  Parses a Jetstream commit payload into a Commit struct.

  ## Example Payload

      %{
        "rev" => "3l3qo2vutsw2b",
        "operation" => "create",
        "collection" => "app.bsky.feed.like",
        "rkey" => "3l3qo2vuowo2b",
        "record" => %{
          "$type" => "app.bsky.feed.like",
          "createdAt" => "2024-09-09T19:46:02.102Z",
          "subject" => %{...}
        },
        "cid" => "bafyreidwaivazkwu67xztlmuobx35hs2lnfh3kolmgfmucldvhd3sgzcqi"
      }
  """
  @spec from(String.t(), integer(), map()) :: t()
  def from(
        did,
        time_us,
        %{
          "rev" => rev,
          "operation" => operation,
          "collection" => collection,
          "rkey" => rkey
        } = commit
      ) do
    %__MODULE__{
      did: did,
      time_us: time_us,
      operation: parse_operation(operation),
      collection: collection,
      rkey: rkey,
      rev: rev,
      record: Map.get(commit, "record"),
      cid: Map.get(commit, "cid")
    }
  end

  @spec parse_operation(String.t()) :: operation()
  defp parse_operation("create"), do: :create
  defp parse_operation("update"), do: :update
  defp parse_operation("delete"), do: :delete
end
