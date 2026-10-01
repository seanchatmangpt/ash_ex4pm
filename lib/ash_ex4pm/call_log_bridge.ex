defmodule AshEx4pm.CallLogBridge do
  @moduledoc """
  Bridges `Ex4pm.Engine.CallLog` into an Ash-side process.

  Not started automatically. `start_link/1` subscribes to the call log,
  attaches a `[:ex4pm, :engine, :call, :stop]` telemetry handler, ingests each
  envelope through `Ex4pm.Stream.Ingest.ingest_envelope/2` into an
  `Ex4pm.Evidence` store, and retains the last `:limit` call summaries.

  ex4pm >= 26.10.1 ships `Ex4pm.Evidence.Store` as a node singleton (its
  GenServer name and its ETS table both default to the module name), so the
  bridge attaches to the already-running store when one exists instead of
  failing to start a second copy; per-bridge isolation lives in the counters
  and summaries, not in the receipt store.

  A refused or failed ingestion is recorded (`stats/1`) and never crashes the
  bridge. The telemetry handler is detached on terminate.

  Options: `:name`, `:limit` (default 100).
  """

  use GenServer

  alias Ex4pm.Engine.CallLog
  alias Ex4pm.Stream.Ingest

  @telemetry_event [:ex4pm, :engine, :call, :stop]

  # ---- API ------------------------------------------------------------

  def start_link(opts \\ []) do
    gen_opts = if opts[:name], do: [name: opts[:name]], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Most recent call summaries, oldest first."
  def calls(server), do: GenServer.call(server, :calls)

  @doc "Counters: `ingested`, `duplicates`, `refused`, `telemetry`, plus `refusals` (last few)."
  def stats(server), do: GenServer.call(server, :stats)

  @doc "The bridge's own evidence store pid."
  def store(server), do: GenServer.call(server, :store)

  @doc "Summaries whose artifact (`artifact:<sha>` or bare `<sha>`) or `subject_digest` equals `key`."
  def correlate(server, key), do: GenServer.call(server, {:correlate, key})

  @doc "Feeds an envelope through the same ingestion path (used for refusal checks)."
  def ingest(server, envelope), do: GenServer.call(server, {:ingest, envelope})

  # ---- callbacks ------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok, store} = start_store()
    :ok = CallLog.subscribe()

    handler_id = {__MODULE__, make_ref()}
    me = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @telemetry_event,
        &__MODULE__.handle_telemetry/4,
        me
      )

    {:ok,
     %{
       store: store,
       handler_id: handler_id,
       limit: Keyword.get(opts, :limit, 100),
       calls: [],
       stats: %{ingested: 0, duplicates: 0, refused: 0, telemetry: 0, refusals: []}
     }}
  end

  @doc false
  def handle_telemetry(_event, _measurements, _meta, pid), do: send(pid, :telemetry_stop)

  @impl true
  def handle_call(:calls, _from, s), do: {:reply, Enum.reverse(s.calls), s}
  def handle_call(:stats, _from, s), do: {:reply, s.stats, s}
  def handle_call(:store, _from, s), do: {:reply, s.store, s}

  def handle_call({:correlate, key}, _from, s) do
    bare = String.replace_prefix(to_string(key), "artifact:", "")

    hits =
      s.calls
      |> Enum.reverse()
      |> Enum.filter(fn c ->
        c.artifact == bare or c.artifact == key or c.subject_digest == key
      end)

    {:reply, hits, s}
  end

  def handle_call({:ingest, envelope}, _from, s) do
    {result, s} = do_ingest(envelope, s)
    {:reply, result, s}
  end

  @impl true
  def handle_info({:ex4pm_engine_call, envelope}, s) do
    {_result, s} = do_ingest(envelope, s)
    {:noreply, remember(envelope, s)}
  end

  def handle_info(:telemetry_stop, s),
    do: {:noreply, update_in(s.stats.telemetry, &(&1 + 1))}

  def handle_info(_other, s), do: {:noreply, s}

  @impl true
  def terminate(_reason, s) do
    :telemetry.detach(s.handler_id)
    CallLog.unsubscribe()
    :ok
  end

  # ---- internals ------------------------------------------------------

  # Ex4pm.Evidence.Store is a node singleton on ex4pm >= 26.10.1 (named
  # GenServer + named ETS table, both the module name). Attach to the running
  # instance when present; only the first bridge in the VM starts a fresh one.
  defp start_store do
    case GenServer.start_link(Ex4pm.Evidence.Store, []) do
      {:ok, store} -> {:ok, store}
      {:error, {:already_started, store}} -> {:ok, store}
    end
  end

  defp do_ingest(envelope, s) do
    result =
      try do
        Ingest.ingest_envelope(envelope, store: s.store)
      rescue
        e -> {:error, {:ingest_crashed, Exception.message(e)}}
      catch
        kind, reason -> {:error, {kind, inspect(reason)}}
      end

    stats =
      case result do
        {:ok, %{status: :ingested}} ->
          %{s.stats | ingested: s.stats.ingested + 1}

        {:ok, %{status: :duplicate_ignored}} ->
          %{s.stats | duplicates: s.stats.duplicates + 1}

        {:error, reason} ->
          %{
            s.stats
            | refused: s.stats.refused + 1,
              refusals: Enum.take([reason | s.stats.refusals], 10)
          }

        other ->
          %{
            s.stats
            | refused: s.stats.refused + 1,
              refusals: Enum.take([{:unexpected, other} | s.stats.refusals], 10)
          }
      end

    {result, %{s | stats: stats}}
  end

  defp remember(envelope, s) do
    summary = summarize(envelope)
    %{s | calls: Enum.take([summary | s.calls], s.limit)}
  end

  defp summarize(%{"events" => [event | _]} = envelope) do
    rels = Map.new(event["relationships"] || [], &{&1["qualifier"], &1["objectId"]})
    attrs = event["attributes"] || %{}

    %{
      activity: event["activity"],
      timestamp: event["timestamp"],
      sequence: envelope["sequence"],
      engine: rels["engine"],
      artifact: rels["artifact"] && String.replace_prefix(rels["artifact"], "artifact:", ""),
      run: rels["run"],
      standing: attrs["standing"],
      refusal: attrs["refusal"],
      replay_verified: attrs["replay_verified"],
      duration_ms: attrs["duration_ms"],
      subject_digest: attrs["subject_digest"]
    }
  end

  defp summarize(_), do: %{activity: nil, artifact: nil, subject_digest: nil}
end
