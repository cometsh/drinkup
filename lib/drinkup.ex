defmodule Drinkup.Firehose do
  alias Drinkup.Firehose
  require Logger

  use WebSockex

  @default_host "https://bsky.network"

  @op_regular 1
  @op_error -1

  # TODO: switch to Gun and GenServer?

  def start_link(opts \\ []) do
    opts = Keyword.validate!(opts, host: @default_host)
    host = Keyword.get(opts, :host)
    cursor = Keyword.get(opts, :cursor)

    url =
      "#{host}/xrpc/com.atproto.sync.subscribeRepos"
      |> URI.new!()
      |> URI.append_query(URI.encode_query(%{cursor: cursor}))
      |> URI.to_string()

    WebSockex.start_link(url, __MODULE__, %{cursor: cursor})
  end

  def handle_connect(conn, state) do
    Logger.info("Connected to Firehose at #{conn.host}#{conn.path}")
    {:ok, state}
  end

  def handle_frame({:binary, msg}, state) do
    with {:ok, header, next} <- CAR.DagCbor.decode(msg),
         {:ok, payload, _} <- CAR.DagCbor.decode(next),
         {%{"op" => @op_regular, "t" => type}, _} <- {header, payload},
         message <- from_payload(type, payload) do
      case message do
        %Firehose.Commit{} = commit ->
          IO.inspect(commit.ops, label: commit.repo)

        msg ->
          IO.inspect(msg)
      end
    else
      {%{"op" => @op_error, "t" => type}, payload} ->
        Logger.error("Got error from Firehose: #{inspect({type, payload})}")

      {:error, reason} ->
        Logger.warning("Failed to decode frame from Firehose: #{inspect(reason)}")
    end

    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    Logger.warning("Got unexpected text frame from Firehose #{inspect(msg)}")
    {:ok, state}
  end

  @spec from_payload(String.t(), map()) ::
          Firehose.Commit.t()
          | Firehose.Sync.t()
          | Firehose.Identity.t()
          | Firehose.Account.t()
          | Firehose.Info.t()
          | nil
  def from_payload("#commit", payload), do: Firehose.Commit.from(payload)
  def from_payload("#sync", payload), do: Firehose.Sync.from(payload)
  def from_payload("#identity", payload), do: Firehose.Identity.from(payload)
  def from_payload("#account", payload), do: Firehose.Account.from(payload)
  def from_payload("#info", payload), do: Firehose.Info.from(payload)
  def from_payload(_type, _payload), do: nil
end
