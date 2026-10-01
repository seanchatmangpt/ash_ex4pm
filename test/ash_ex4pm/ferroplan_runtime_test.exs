defmodule AshEx4pm.FerroplanRuntimeTest do
  use ExUnit.Case, async: true

  alias AshEx4pm.FerroplanRuntime

  @domain "(define (domain d) (:requirements :strips) (:predicates (a) (b)) " <>
            "(:action go :parameters () :precondition (a) :effect (and (b) (not (a)))))"
  @problem "(define (problem p) (:domain d) (:init (a)) (:goal (b)))"
  @unsolvable "(define (problem q) (:domain d) (:init) (:goal (b)))"

  test "owns no planner: provider is ex4pm's own Ex4pm.Engine.Ferroplan" do
    assert FerroplanRuntime.provider() == Ex4pm.Engine.Ferroplan
    assert FerroplanRuntime.missing_contract() == []
    assert FerroplanRuntime.available?()
  end

  test "standing is :alive with the packaged wasm artifact present" do
    assert {:alive, %{provider: Ex4pm.Engine.Ferroplan, wasm_built?: true}} =
             FerroplanRuntime.standing()
  end

  test "plan/4 solves a real PDDL problem through the packaged ferroplan wasm" do
    assert {:ok, %{"solved" => true, "plan" => %{"length" => 1, "steps" => [step]}}} =
             FerroplanRuntime.plan(@domain, @problem)

    assert step["action"] == "GO"
  end

  test "plan/4 reports an unsolvable problem as unsolved, not a crash" do
    assert {:ok, %{"solved" => false}} = FerroplanRuntime.plan(@domain, @unsolvable)
  end

  test "plan_production/4 returns a candidate-only operation envelope" do
    assert {:ok, %{} = envelope} = FerroplanRuntime.plan_production(@domain, @problem)
    assert map_size(envelope) > 0
  end

  test "readiness/1 returns the engine capability manifest" do
    assert {:ok, %{} = manifest} = FerroplanRuntime.readiness()
    assert map_size(manifest) > 0
  end

  test "a missing provider contract is a typed refusal, never a guess" do
    # wasm_built?/0 is required too: standing/0 applies it for the alive verdict,
    # so a provider lacking it must refuse, not crash.
    assert FerroplanRuntime.required_contract() == [
             plan: 4,
             plan_production: 4,
             readiness: 1,
             version: 1,
             wasm_built?: 0
           ]
  end
end
