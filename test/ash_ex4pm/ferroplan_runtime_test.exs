defmodule AshEx4pm.FerroplanRuntimeTest do
  use ExUnit.Case, async: true

  alias AshEx4pm.FerroplanRuntime

  test "owns no planner: provider is ex4pm's own Ex4pm.Engine.Ferroplan" do
    assert FerroplanRuntime.provider() == Ex4pm.Engine.Ferroplan
    assert FerroplanRuntime.required_contract()[:plan_production] == 4
  end

  test "until ex4pm ships the ferroplan runtime every call is a typed refusal and standing is :partial_alive" do
    unless FerroplanRuntime.available?() do
      assert {:partial_alive, %{provider: Ex4pm.Engine.Ferroplan, missing: missing}} =
               FerroplanRuntime.standing()

      assert missing == FerroplanRuntime.required_contract()

      assert {:error, {:ferroplan_runtime_unavailable, %{provider: Ex4pm.Engine.Ferroplan}}} =
               FerroplanRuntime.plan("(define (domain d))", "(define (problem p))")

      assert {:error, {:ferroplan_runtime_unavailable, _}} = FerroplanRuntime.readiness()
    end
  end

  test "once ex4pm ships the ferroplan runtime readiness is delegated to the real engine" do
    if FerroplanRuntime.available?() and apply(Ex4pm.Engine.Ferroplan, :wasm_built?, []) do
      assert {:alive, %{wasm_built?: true}} = FerroplanRuntime.standing()
      assert {:ok, %{} = _manifest} = FerroplanRuntime.readiness()
    end
  end
end
