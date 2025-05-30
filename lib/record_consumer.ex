defmodule Drinkup.RecordConsumer do
  @moduledoc """
  An opinionated consumer of the Firehose that eats consumers
  """

  @callback handle_create(any()) :: any()
  @callback handle_update(any()) :: any()
  @callback handle_delete(any()) :: any()

  defmacro __using__(opts) do
    {collections, _opts} = Keyword.pop(opts, :collections, [])

    quote location: :keep do
      @behaviour Drinkup.Consumer
      @behaviour Drinkup.RecordConsumer

      def handle_event(%Drinkup.Event.Commit{} = event) do
        event.ops
        |> Enum.filter(fn %{path: path} ->
          path |> String.split("/") |> Enum.at(0) |> matches_collections?()
        end)
        |> Enum.map(&Drinkup.RecordConsumer.Record.from(&1, event.repo))
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
    alias Drinkup.Event.Commit.RepoOp
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
