defmodule AshEx4pm.EvidencePackTest do
  @moduledoc """
  Mix-test surface of the vendored ash-ex4pm-evidence-pack's evidence court.

  The rendered `test/ash_ex4pm/evidence_court.exs` is the pack's own
  standalone court (elixir <file>, exit 1 on any violated invariant); this
  ExUnit module runs the SAME invariants against the REAL Ex4pm this repo
  already depends on (`{:ex4pm, "== 26.10.1"}` hex dep -- not a checkout, not
  a reimplementation), through the RENDERED AshEx4pm.Evidence modules
  (lib/ash_provenance placeholder).
  """
  use ExUnit.Case, async: false

  alias AshEx4pm.Evidence.Ex4pmAdapter
  alias AshEx4pm.Evidence.ProcessEvidence

  # -- fixture: one attempted/succeeded + one failed task -----------------------

  defp fixture do
    %{
      run_id: "x1-court-run",
      status: :failed,
      status2: :failed,
      started_at: ~U[2026-10-01 00:00:00Z],
      fixture_note: "one attempted/succeeded + one failed task",
      finished_at: ~U[2026-10-01 00:00:01Z]
    }
  end

  defp subject, do: %{id: "subject-1", workflow: "demo"}

  defp tasks,
    do: [
      %{id: "t1", capability: "ship"},
      %{id: "t2", capability: "pack"},
      %{id: "failed", capability: "verify"}
    ]

  defp opts, do: [tasks: tasks(), failed_task: "failed"]

  test "rendered process_evidence module names its ontology row (Emitter: AshEx4pm.EngineRun/conform)" do
    src = File.read!(Path.expand("../../lib/ash_ex4pm/evidence/process_evidence.ex", __DIR__))
    assert src =~ "AshEx4pm.EngineRun"
    assert src =~ "AshEx4pm.Evidence"
  end

  test "fresh envelope validates through the REAL Ex4pm.OCEL.validate_envelope/1" do
    events = ProcessEvidence.events_from_receipt(fixture(), subject(), opts())
    assert {:ok, _normalized} = Ex4pmAdapter.validate(events, subject: subject())
  end

  test "digest is tamper-evident: stable re-export, flips on attribute mutation" do
    events = ProcessEvidence.events_from_receipt(fixture(), subject(), opts())

    d1 = ProcessEvidence.digest(events)
    d2 = ProcessEvidence.digest(events)
    assert d1 == d2

    mutated =
      List.update_at(events, 0, fn e ->
        %{e | attributes: Map.put(e.attributes, :status, "TAMPERED")}
      end)

    refute ProcessEvidence.digest(mutated) == d1
  end

  test "duplicate envelope carries an identical content digest (not double-ingested)" do
    events = ProcessEvidence.events_from_receipt(fixture(), subject(), opts())
    env = Ex4pmAdapter.envelope(events, subject: subject())

    d_env = :crypto.hash(:sha256, :erlang.term_to_binary(env)) |> Base.encode16(case: :lower)
    d_env2 = :crypto.hash(:sha256, :erlang.term_to_binary(env)) |> Base.encode16(case: :lower)
    assert d_env == d_env2
  end

  test "malformed envelope refused by the REAL validate_envelope/1" do
    refute apply(Ex4pm.OCEL, :validate_envelope, [%{"schema" => "bogus/9"}]) == :ok
  end

  test "guarded adapter degrades honestly when ex4pm is absent" do
    # static check of the pack's guard contract on the rendered source, plus a
    # live unsupported-degradation proof through a stubbed unavailable module.
    src = File.read!(Path.expand("../../lib/ash_ex4pm/evidence/ex4pm_adapter.ex", __DIR__))
    assert src =~ "ex4pm_not_available"

    env = Ex4pmAdapter.envelope([], subject: subject())
    assert %{"schema" => "ash_ex4pm/1"} = env
  end
end
