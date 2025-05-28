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

    WebSockex.start_link(url, __MODULE__, 0)
  end

  def handle_connect(conn, state) do
    Logger.info("Connected to Firehose at #{conn.host}#{conn.path}")
    {:ok, state}
  end

  def handle_frame({:binary, msg}, state) do
    with {:ok, header, next} <- CAR.DagCbor.decode(msg),
         {:ok, payload, _} <- CAR.DagCbor.decode(next),
         {%{"op" => @op_regular, "t" => type}, _} <- {header, payload},
         true <- type == "#info" || valid_seq?(state, payload["seq"]),
         message <-
           from_payload(type, payload) do
      case message do
        %Firehose.Commit{} = commit ->
          IO.inspect(commit.ops, label: commit.repo)

        msg ->
          IO.inspect(msg)
      end

      {:ok, payload["seq"] || state}
    else
      false ->
        Logger.error("Got out of sequence or invalid `seq` from Firehose")
        {:ok, state}

      {%{"op" => @op_error, "t" => type}, payload} ->
        Logger.error("Got error from Firehose: #{inspect({type, payload})}")
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Failed to decode frame from Firehose: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_frame({:text, msg}, state) do
    Logger.warning("Got unexpected text frame from Firehose: #{inspect(msg)}")
    {:ok, state}
  end

  @spec valid_seq?(integer(), any()) :: boolean()
  defp valid_seq?(last_seq, seq) when is_integer(seq), do: seq > last_seq
  defp valid_seq?(_last_seq, _seq), do: false

  @spec from_payload(String.t(), map()) ::
          Firehose.Commit.t()
          | Firehose.Sync.t()
          | Firehose.Identity.t()
          | Firehose.Account.t()
          | Firehose.Info.t()
          | nil
  defp from_payload("#commit", payload), do: Firehose.Commit.from(payload)
  defp from_payload("#sync", payload), do: Firehose.Sync.from(payload)
  defp from_payload("#identity", payload), do: Firehose.Identity.from(payload)
  defp from_payload("#account", payload), do: Firehose.Account.from(payload)
  defp from_payload("#info", payload), do: Firehose.Info.from(payload)
  defp from_payload(_type, _payload), do: nil
end
