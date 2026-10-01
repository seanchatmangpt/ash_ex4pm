defmodule AshEx4pm.Test.ProjRecord do
  @moduledoc false
  defstruct [:standing, :replay_verified, :artifact_sha256]
end

defmodule AshEx4pm.CapabilityProjectionTest do
  use ExUnit.Case, async: false

  alias AshEx4pm.CapabilityProjection, as: P

  @artifact System.get_env("WASM4PM_EX4PM_WASM")

  defp result(standing, evidence) do
    %Ex4pm.Engine.Result{
      engine: :wasm,
      operation: :discover,
      subject_hash: "h",
      standing: standing,
      value: %{},
      evidence: evidence
    }
  end

  @good %{
    replay_verified: true,
    identity_observed: true,
    transport_identity: %{wasm_sha256: "abc"},
    wasm4pm_source_sha: "src",
    request_digest: "req",
    result_digest: "res"
  }

  test "alive + replay + sha + observed identity is admitted" do
    p = P.from_result({:ok, result(:alive, @good)})
    assert p.admitted and p.replay_verified
    assert p.artifact_sha256 == "abc"
    assert {p.engine, p.operation, p.source_sha} == {:wasm, :discover, "src"}
    assert {p.request_digest, p.result_digest} == {"req", "res"}
    assert P.to_map(p).admitted == true
  end

  test "evidence.wasm_sha256 takes precedence over transport identity" do
    p = P.from_result(result(:alive, Map.put(@good, :wasm_sha256, "top")))
    assert p.artifact_sha256 == "top"
  end

  test "each missing admission term refuses admission" do
    refute P.from_result(result(:partial_alive, @good)).admitted
    refute P.from_result(result(:alive, %{@good | replay_verified: false})).admitted
    refute P.from_result(result(:alive, %{@good | identity_observed: false})).admitted
    refute P.from_result(result(:alive, Map.delete(@good, :transport_identity))).admitted
  end

  test "typed refusal projects refusal_code and is not admitted" do
    ref = Ex4pm.Refusal.new(:no_engine, "nope")
    p = P.from_result({:error, ref})
    assert p.refusal_code == :no_engine
    refute p.admitted
  end

  test "project/3 without transports yields a refusal projection" do
    p = P.project(:discover, %{traces: [["a", "b"]]}, [])
    refute p.admitted
    assert is_atom(p.refusal_code) and p.refusal_code != nil
  end

  test "calculation derives admitted from stored fields" do
    alias AshEx4pm.Calculations.CapabilityProjection, as: C
    ok = %AshEx4pm.Test.ProjRecord{standing: :alive, replay_verified: true, artifact_sha256: "x"}

    bad = %AshEx4pm.Test.ProjRecord{
      standing: :alive,
      replay_verified: false,
      artifact_sha256: "x"
    }

    assert C.calculate([ok, bad], [], %{}) == [true, false]
  end

  describe "real wasm" do
    cond do
      @artifact in [nil, ""] ->
        @tag skip: "WASM4PM_EX4PM_WASM unset: no real wasm4pm artifact to execute"

      not File.regular?(@artifact) ->
        @tag skip: "WASM4PM_EX4PM_WASM is not a regular file"

      not Code.ensure_loaded?(Ex4pmEngine.Wasm.RealTransport) ->
        @tag skip: "RealTransport not available"

      true ->
        :ok
    end

    test "project/3 over the real artifact is admitted with the real sha256" do
      {:ok, transports} = Ex4pmEngine.Wasm.RealTransport.all_transports(@artifact)
      p = P.project(:discover, %{traces: [["a", "b", "c"]]}, transports)
      assert p.admitted
      assert p.standing == :alive
      assert p.artifact_sha256 == Ex4pm.Core.Hash.digest(File.read!(@artifact))
    end
  end
end
