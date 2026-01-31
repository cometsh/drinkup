defmodule Drinkup.Firehose.RecordConsumer do
  @moduledoc """
  Opinionated consumer of the Firehose focused on record operations.

  This is an abstraction over the core `Drinkup.Firehose` implementation
  designed for easily handling `commit` events, with the ability to filter by
  collection. It's similiar to `Drinkup.Jetstream`, but using the Firehose
  directly (and currently more naive).

  ## Example

      defmodule MyRecordConsumer do
        use Drinkup.Firehose.RecordConsumer,
          collections: ["app.bsky.feed.post", ~r/app\\.bsky\\.graph\\..+/],
          name: :my_records,
          host: "https://bsky.network"

        @impl true
        def handle_create(record) do
          IO.inspect(record, label: "New record")
        end

        @impl true
        def handle_delete(record) do
          IO.inspect(record, label: "Deleted record")
        end
      end

      # In your application supervision tree:
      children = [MyRecordConsumer]

  ## Options

  All options from `Drinkup.Firehose` are supported, plus:

  - `:collections` - List of collection NSIDs (strings or regexes) to filter. If
    empty or not provided, all collections are processed.

  ## Callbacks

  Implement these callbacks to handle different record actions:

  - `handle_create/1` - Called when a record is created
  - `handle_update/1` - Called when a record is updated
  - `handle_delete/1` - Called when a record is deleted

  All callbacks receive a `Drinkup.Firehose.RecordConsumer.Record` struct.
  """

  @callback handle_create(any()) :: any()
  @callback handle_update(any()) :: any()
  @callback handle_delete(any()) :: any()

  defmacro __using__(opts) do
    {collections, firehose_opts} = Keyword.pop(opts, :collections, [])

    quote location: :keep do
      use Drinkup.Firehose, unquote(firehose_opts)
      @behaviour Drinkup.Firehose.RecordConsumer

      @impl true
      def handle_event(%Drinkup.Firehose.Event.Commit{} = event) do
        event.ops
        |> Enum.filter(fn %{path: path} ->
          path |> String.split("/") |> Enum.at(0) |> matches_collections?()
        end)
        |> Enum.map(&Drinkup.Firehose.RecordConsumer.Record.from(&1, event.repo))
        |> Enum.each(&apply(__MODULE__, :"handle_#{&1.action}", [&1]))
      end

      def handle_event(_event), do: :noop

      unquote(
        if collections == [] do
          quote do
            def matches_collections?(_type), do: true
          end
        else
          quote do
            def matches_collections?(nil), do: false

            def matches_collections?(type) when is_binary(type),
              do:
                Enum.any?(unquote(collections), fn
                  matcher when is_binary(matcher) -> type == matcher
                  matcher -> Regex.match?(matcher, type)
                end)
          end
        end
      )

      @impl true
      def handle_create(_record), do: nil
      @impl true
      def handle_update(_record), do: nil
      @impl true
      def handle_delete(_record), do: nil

      defoverridable handle_create: 1, handle_update: 1, handle_delete: 1
    end
  end

  defmodule Record do
    alias Drinkup.Firehose.Event.Commit.RepoOp
    use TypedStruct

    typedstruct do
      field :type, String.t()
      field :rkey, String.t()
      field :did, String.t()
      field :action, :create | :update | :delete
      field :cid, binary() | nil
      field :record, map() | nil
    end

    @spec from(RepoOp.t(), String.t()) :: t()
    def from(%RepoOp{action: action, path: path, cid: cid, record: record}, did) do
      [type, rkey] = String.split(path, "/")

      %__MODULE__{
        type: type,
        rkey: rkey,
        did: did,
        action: action,
        cid: cid,
        record: record
      }
    end
  end
end
