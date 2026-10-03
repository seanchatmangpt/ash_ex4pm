defmodule AshEx4pm.Evidence.ProcessEvidence do
  @moduledoc """
  Process evidence: events of a workflow run, a pure OCEL 2.0 JSON export and a
  tamper-evident content digest. Rendered by packs/ash-ex4pm-evidence-pack from
  the Emitter row for the consumer's own `AshEx4pm.EngineRun` Ash resource
  (`conform` action). No producer module is embedded.
  """

  defmodule Event do
    @moduledoc "One process-evidence event: activity over qualified objects, bound to a subject."
    @enforce_keys [:id, :activity, :timestamp]
    defstruct id: nil,
              activity: nil,
              timestamp: nil,
              objects: [],
              attributes: %{},
              subject_id: nil

    @type object :: {String.t(), String.t(), String.t()}
    @type t :: %__MODULE__{
            id: String.t(),
            activity: String.t(),
            timestamp: DateTime.t(),
            objects: [object()],
            attributes: map(),
            subject_id: String.t() | nil
          }
  end

  @callback events(receipt :: map(), subject :: map(), opts :: keyword()) :: [Event.t()]
  @callback export([Event.t()], :ocel2_json) :: {:ok, String.t()} | {:error, map()}

  @doc """
  Turn a receipt plus subject into events: an `attempted`/`succeeded` pair per task
  (`failed` instead of `succeeded` for `opts[:failed_task]` or when the receipt did
  not succeed; tasks after a failure are not attempted).

  Options: `:tasks` (list of maps/structs with `:id` and `:capability`; default `[]`),
  `:realizations` (task id => term), `:run_prefix` (default "run:").
  """
  @spec events_from_receipt(map(), map(), keyword()) :: [Event.t()]
  def events_from_receipt(receipt, subject, opts \\ []) do
    tasks = Keyword.get(opts, :tasks, [])
    reals = Keyword.get(opts, :realizations, %{})
    failed = Keyword.get(opts, :failed_task)
    run_prefix = Keyword.get(opts, :run_prefix, "run:")
    run = run_prefix <> run_id(receipt)
    sid = Map.get(subject, :id)
    status = Map.get(receipt, :status)
    ok? = status == :succeeded

    {evs, _} =
      Enum.reduce(tasks, {[], false}, fn t, {acc, dead?} ->
        if dead? do
          {acc, true}
        else
          id = to_string(Map.get(t, :id))
          cap = to_string(Map.get(t, :capability))
          real = to_string(Map.get(reals, t.id) || Map.get(reals, id) || "unrealized:" <> id)

          objs = [
            {"WorkflowRun", run, "run"},
            {"Capability", "cap:" <> cap, "capability"},
            {"Realization", "real:" <> real, "realization"}
          ]

          failed_here? = failed != nil and to_string(failed) == id
          base = %{task: id, status: to_string(status)}
          ts = Map.get(receipt, :started_at)

          att = ev("#{run}/#{id}/attempted", "task_attempted", ts, objs, base, sid)

          {last, dead} =
            cond do
              failed_here? ->
                {ev("#{run}/#{id}/failed", "task_failed", finished_at(receipt), objs, base, sid),
                 true}

              ok? ->
                {ev(
                   "#{run}/#{id}/succeeded",
                   "task_succeeded",
                   finished_at(receipt),
                   objs,
                   base,
                   sid
                 ), false}

              true ->
                {nil, false}
            end

          {acc ++ [att] ++ List.wrap(last), dead}
        end
      end)

    evs
  end

  defp run_id(receipt) do
    case Map.get(receipt, :run_id) do
      nil -> "unknown"
      id -> to_string(id)
    end
  end

  defp finished_at(receipt), do: Map.get(receipt, :finished_at) || Map.get(receipt, :started_at)

  defp ev(id, act, ts, objs, attrs, sid),
    do: %Event{
      id: id,
      activity: act,
      timestamp: ts,
      objects: objs,
      attributes: attrs,
      subject_id: sid
    }

  @doc "Pure OCEL 2.0 JSON export (objectTypes/eventTypes/objects/events)."
  @spec export([Event.t()], :ocel2_json) :: {:ok, String.t()} | {:error, map()}
  def export(events, :ocel2_json) when is_list(events) do
    objects =
      events
      |> Enum.flat_map(& &1.objects)
      |> Enum.uniq_by(fn {_t, id, _q} -> id end)
      |> Enum.sort()

    otypes = objects |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    etypes = events |> Enum.map(& &1.activity) |> Enum.uniq() |> Enum.sort()

    doc = %{
      "objectTypes" => Enum.map(otypes, &%{"name" => &1, "attributes" => []}),
      "eventTypes" =>
        Enum.map(etypes, fn a ->
          keys =
            events
            |> Enum.filter(&(&1.activity == a))
            |> Enum.flat_map(&Map.keys(&1.attributes))
            |> Enum.map(&to_string/1)
            |> Enum.uniq()
            |> Enum.sort()

          %{"name" => a, "attributes" => Enum.map(keys, &%{"name" => &1, "type" => "string"})}
        end),
      "objects" =>
        Enum.map(objects, fn {t, id, _q} -> %{"id" => id, "type" => t, "attributes" => []} end),
      "events" =>
        Enum.map(events, fn e ->
          %{
            "id" => e.id,
            "type" => e.activity,
            "time" => DateTime.to_iso8601(e.timestamp),
            "attributes" =>
              Enum.map(
                Map.put(e.attributes, :subject_id, e.subject_id),
                fn {k, v} -> %{"name" => to_string(k), "value" => to_string(v)} end
              ),
            "relationships" =>
              Enum.map(e.objects, fn {_t, id, q} -> %{"objectId" => id, "qualifier" => q} end)
          }
        end)
    }

    if Code.ensure_loaded?(Jason) do
      {:ok, apply(Jason, :encode!, [doc])}
    else
      {:error, %{reason: :unsupported, detail: :jason_not_available}}
    end
  end

  def export(_events, format), do: {:error, %{reason: :unsupported_format, format: format}}

  @doc """
  Tamper-evident content digest over the evidence: sha256 over
  term_to_binary of each event's {id, activity, attributes}. Any change to any
  event attribute flips the digest (LedgerOCEL.digest lineage).
  """
  @spec digest([Event.t()]) :: String.t()
  def digest(events) when is_list(events) do
    events
    |> Enum.map(&{&1.id, &1.activity, &1.attributes})
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
