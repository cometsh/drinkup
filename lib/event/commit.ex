defmodule Drinkup.Event.Commit do
  @moduledoc """
  Struct for commit events from the ATProto Firehose.
  """

  # TODO: see atp specs
  @type tid() :: String.t()

  alias __MODULE__.RepoOp
  use TypedStruct

  typedstruct enforce: true do
    field :seq, integer()
    # DEPCREATED
    field :rebase, bool()
    # DEPRECATED
    field :too_big, bool()
    field :repo, String.t()
    field :commit, binary()
    field :rev, tid()
    field :since, tid() | nil
    field :blocks, CAR.Archive.t()
    field :ops, list(RepoOp.t())
    # DEPRECATED
    field :blobs, list(binary())
    field :prev_data, binary(), enforce: nil
    field :time, NaiveDateTime.t()
  end

  @spec from(map()) :: t()
  def from(
        %{
          "seq" => seq,
          "rebase" => rebase,
          "tooBig" => too_big,
          "repo" => repo,
          "commit" => commit,
          "rev" => rev,
          "since" => since,
          "blocks" => %CBOR.Tag{value: blocks},
          "ops" => ops,
          "blobs" => blobs,
          "time" => time
        } = msg
      ) do
    prev_data =
      Map.get(msg, "prevData")

    time = NaiveDateTime.from_iso8601!(time)
    {:ok, blocks} = CAR.decode(blocks)

    %__MODULE__{
      seq: seq,
      rebase: rebase,
      too_big: too_big,
      repo: repo,
      commit: commit,
      rev: rev,
      since: since,
      blocks: blocks,
      ops: Enum.map(ops, &RepoOp.from(&1, blocks)),
      blobs: blobs,
      prev_data: prev_data,
      time: time
    }
  end

  defmodule RepoOp do
    typedstruct enforce: true do
      @type action() :: :create | :update | :delete | String.t()

      field :action, action()
      field :path, String.t()
      field :cid, binary()
      field :prev, binary(), enforce: false
      field :record, map() | nil
    end

    @spec from(map(), CAR.Archive.t()) :: t()
    def from(%{"action" => action, "path" => path, "cid" => cid} = op, %CAR.Archive{} = blocks) do
      prev = Map.get(op, "prev")
      record = CAR.Archive.get_block(blocks, cid)

      %__MODULE__{
        action: recognise_action(action),
        path: path,
        cid: cid,
        prev: prev,
        record: record
      }
    end

    @spec recognise_action(String.t()) :: action()
    defp recognise_action(action) when action in ["create", "update", "delete"],
      do: String.to_atom(action)

    defp recognise_action(action) when is_binary(action), do: action
    defp recognise_action(nil), do: nil
  end
end
