defmodule AshEx4pm.CallLogBridgeTest do
  use ExUnit.Case, async: false

  alias AshEx4pm.CallLogBridge
  alias AshEx4pm.FerroplanRuntime
  alias Ex4pm.Engine.CallLog

  @domain "(define (domain d) (:requirements :strips) (:predicates (a) (b)) " <>
            "(:action go :parameters () :precondition (a) :effect (and (b) (not (a)))))"
  @problem "(define (problem p) (:domain d) (:init (a)) (:goal (b)))"

  setup do
    CallLog.clear()
    {:ok, bridge} = CallLogBridge.start_link(limit: 3)
    on_exit(fn -> if Process.alive?(bridge), do: GenServer.stop(bridge) end)
    %{bridge: bridge}
  end

  # Waits until the bridge has handled `n` ingestions/refusals. Telemetry just
  # needs to have seen the real engine call: ex4pm >= 26.10.1 emits exactly one
  # [:ex4pm, :engine, :call, :stop] per engine call (single CallLog.wrap in
  # Ex4pm.Engine.Ferroplan.run_admitted/4), and direct bridge ingests emit none.
  defp await(bridge, n) do
    Enum.reduce_while(1..100, nil, fn _, _ ->
      s = CallLogBridge.stats(bridge)

      if s.ingested + s.duplicates + s.refused >= n and s.telemetry >= 1,
        do: {:halt, s},
        else:
          (
            Process.sleep(20)
            {:cont, nil}
          )
    end)
  end

  test "real ferroplan call emits telemetry, a valid envelope, and is ingested", %{bridge: b} do
    ref = make_ref()
    me = self()

    :telemetry.attach(
      {ref, :probe},
      [:ex4pm, :engine, :call, :stop],
      fn _e, m, meta, _ -> send(me, {:telemetry, m, meta}) end,
      nil
    )

    assert {:ok, %{"solved" => true}} = FerroplanRuntime.plan(@domain, @problem)
    assert_receive {:telemetry, %{duration: d}, %{engine: _, operation: _, standing: _}}, 5_000
    assert is_integer(d)
    :telemetry.detach({ref, :probe})

    [envelope | _] = CallLog.events()
    assert {:ok, _} = Ex4pm.OCEL.validate_envelope(envelope)

    stats = await(b, 1)
    assert stats.ingested >= 1
    assert stats.refused == 0
    assert stats.telemetry >= 1

    [call | _] = CallLogBridge.calls(b)
    assert call.activity =~ "engine."

    # correlate by subject digest and by artifact
    assert [_ | _] = CallLogBridge.correlate(b, call.subject_digest)

    if call.artifact && call.artifact != "unobserved" do
      assert [_ | _] = CallLogBridge.correlate(b, call.artifact)
    end

    assert CallLogBridge.correlate(b, "no-such-key") == []

    # ingestion state lives in the bridge's own store
    assert length(Ex4pm.Evidence.Store.all(CallLogBridge.store(b))) >= 2
  end

  test "keeps only the last N summaries", %{bridge: b} do
    for _ <- 1..5, do: FerroplanRuntime.plan(@domain, @problem)
    await(b, 5)
    assert length(CallLogBridge.calls(b)) == 3
  end

  test "a refused envelope is recorded and the bridge stays alive", %{bridge: b} do
    assert {:error, _} = CallLogBridge.ingest(b, %{"schema" => "bogus"})
    assert {:error, _} = CallLogBridge.ingest(b, :not_an_envelope)
    assert Process.alive?(b)
    assert CallLogBridge.stats(b).refused == 2

    assert {:ok, _} = FerroplanRuntime.plan(@domain, @problem)
    assert await(b, 3).ingested >= 1
  end

  test "call_log: false yields no envelope and no bridge call", %{bridge: b} do
    assert {:ok, %{"solved" => true}} =
             FerroplanRuntime.plan(@domain, @problem, %{}, call_log: false)

    Process.sleep(200)
    assert CallLog.events() == []
    assert CallLogBridge.calls(b) == []
    assert CallLogBridge.stats(b).ingested == 0
  end

  test "telemetry handler is detached on terminate" do
    before = length(:telemetry.list_handlers([:ex4pm, :engine, :call, :stop]))
    {:ok, b2} = CallLogBridge.start_link([])
    assert length(:telemetry.list_handlers([:ex4pm, :engine, :call, :stop])) == before + 1
    GenServer.stop(b2)
    assert length(:telemetry.list_handlers([:ex4pm, :engine, :call, :stop])) == before
  end
end
