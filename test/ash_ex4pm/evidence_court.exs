Mix.install([{:jason, "~> 1.4"}])

defmodule AshEx4pm.Evidence.EvidenceCourt do
  defp fail(msg),
    do:
      (
        IO.puts("FAIL: " <> msg)
        exit({:shutdown, 1})
      )

  defp pass(msg), do: IO.puts("PASS: " <> msg)

  @ex4pm_root System.get_env("EX4PM_ROOT") || Path.expand("~/ex4pm")

  defp compile_ex4pm do
    root = @ex4pm_root

    files = [
      "lib/ex4pm/core.ex",
      "lib/ex4pm/ocel.ex",
      "lib/ex4pm/evidence.ex",
      "lib/ex4pm/stream/ingest.ex"
    ]

    Enum.each(files, fn rel ->
      path = Path.join(root, rel)

      if File.exists?(path) do
        Code.compile_file(path)
      else
        fail("ex4pm file missing: " <> path)
      end
    end)
  end

  # -- fixture: a receipt with two succeeded tasks and one failed task ---------

  defp fixture do
    %{
      run_id: "demo-run",
      status: :failed,
      started_at: ~U[2026-10-01 00:00:00Z],
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

  # -- invariants ---------------------------------------------------------------

  def run do
    consumer_lib = Path.expand("../../lib/ash_ex4pm/evidence", __DIR__)

    ["process_evidence.ex", "ex4pm_adapter.ex"]
    |> Enum.each(fn f ->
      path = Path.join(consumer_lib, f)
      Code.compile_file(path)
    end)

    compile_ex4pm()

    pe = AshEx4pm.Evidence.ProcessEvidence
    adapter_mod = AshEx4pm.Evidence.Ex4pmAdapter

    events = pe.events_from_receipt(fixture(), subject(), opts())

    # 1. fresh: the adapter envelope passes the REAL validator
    case adapter_mod.validate(events, subject: subject()) do
      {:ok, _normalized} ->
        pass("fresh envelope validates through real Ex4pm.OCEL.validate_envelope/1")

      other ->
        fail("fresh envelope refused: " <> inspect(other))
    end

    # 2. duplicate: same events -> same digest; a mutated attribute flips it
    d1 = pe.digest(events)
    d2 = pe.digest(events)

    if d1 == d2 do
      pass("digest stable across re-export: " <> d1)
    else
      fail("digest unstable: " <> d1 <> " vs " <> d2)
    end

    mutated =
      List.update_at(events, 0, fn e ->
        %{e | attributes: Map.put(e.attributes, :status, "TAMPERED")}
      end)

    if pe.digest(mutated) == d1 do
      fail("digest did NOT flip under tamper -- not tamper-evident")
    else
      pass("digest flips under tamper (tamper-evident)")
    end

    # 3. duplicate: replaying the same envelope is detected, not double-ingested
    env = adapter_mod.envelope(events, subject: subject())
    d_env = :crypto.hash(:sha256, :erlang.term_to_binary(env)) |> Base.encode16(case: :lower)
    d_env2 = :crypto.hash(:sha256, :erlang.term_to_binary(env)) |> Base.encode16(case: :lower)

    if d_env == d_env2 do
      pass("duplicate envelope has identical content digest: " <> d_env)
    else
      fail("duplicate envelope digest mismatch")
    end

    # 4. refusal: the REAL validator refuses a malformed envelope
    case apply(Ex4pm.OCEL, :validate_envelope, [%{"schema" => "bogus/9"}]) do
      :ok -> fail("malformed envelope was ADMITTED -- refusal invariant broken")
      {:error, _} -> pass("malformed envelope refused by real validate_envelope/1")
      other -> fail("unexpected validator response: " <> inspect(other))
    end
  end
end

# -- runner -------------------------------------------------------------------
AshEx4pm.Evidence.EvidenceCourt.run()
