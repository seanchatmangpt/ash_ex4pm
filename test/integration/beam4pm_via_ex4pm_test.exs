defmodule AshEx4pm.BeamPMViaEx4pmTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Chicago-style (real collaborators, state-based assertions) integration
  test proving the full facade chain -- ash_ex4pm -> the REAL `ex4pm`
  Hex dependency's `Ex4pm.Engine.Beam4pm` -> a real HTTP request -> a real
  local Ash/AshJsonApi/Bandit server standing in for beam4pm (its own
  json_api surface is not mounted yet, so no live beam4pm to hit) -- runs
  together in one test suite, in this repo, rather than each layer being
  exercised only in its own repo's tests as before. No mocking library
  anywhere in this file: `MicroBeam4pm` (test/support/micro_beam4pm.ex) is
  a real Ash resource + real AshJsonApi.Router + a real Bandit HTTP
  listener on a real OS port, and every assertion below is on real
  returned/observed state (HTTP status, decoded JSON body, refusal
  struct fields) -- never an interaction/call-count assertion.

  This suite intentionally exercises `Ex4pm.Engine.Beam4pm` directly
  (ash_ex4pm's real, published runtime dependency) for the two currently
  LIVE admitted operations (`:beam4pm_ocel_events`,
  `:beam4pm_conformance_results`), and separately documents, as a real
  passing assertion rather than silence, that the currently pinned
  `ex4pm == 26.9.9` release does not yet admit `:htn_plan`/`:fond_policy`
  at all (they were added in an ontology change released after this pin),
  plus the honest current state of
  `AshEx4pm.AutomatedPlanning` (still empty of `htn_plan/2`/`fond_policy/2`
  because this repo's `{:ex4pm, "== 26.9.9"}` pin predates the ontology
  release carrying those individuals -- see
  `lib/ash_ex4pm/automated_planning.ex`'s own moduledoc). That assertion
  is a deliberate canary: it will start FAILING, on purpose, the moment
  the `ex4pm` pin is bumped to a release that carries the htn_plan/
  fond_policy individuals and this suite is not yet updated -- surfacing
  the drift immediately instead of silently going stale.
  """

  alias Ex4pm.Engine.Beam4pm

  defp start_micro_beam4pm! do
    port = Enum.random(21_000..21_999)
    {:ok, pid} = Bandit.start_link(plug: MicroBeam4pm.Router, port: port, ip: {127, 0, 0, 1})
    on_exit(fn -> Process.exit(pid, :normal) end)
    "http://127.0.0.1:#{port}"
  end

  setup do
    {:ok, base_url: start_micro_beam4pm!()}
  end

  describe "ash_ex4pm's real dependency chain reaches a real beam4pm-shaped server" do
    test "seeding an ocel_event through the real fixture and reading it back through Ex4pm.Engine.Beam4pm (the real ex4pm dependency)",
         %{base_url: base_url} do
      seed_response =
        Req.post!(base_url <> "/ocel_event",
          headers: [{"content-type", "application/vnd.api+json"}],
          json: %{
            "data" => %{
              "type" => "ocel_event",
              "attributes" => %{"activity" => "ash_ex4pm_chicago_integration_probe"}
            }
          }
        )

      assert seed_response.status == 201
      %{"data" => %{"id" => id, "attributes" => attrs}} = seed_response.body
      assert attrs["activity"] == "ash_ex4pm_chicago_integration_probe"

      {:ok, result} = Beam4pm.execute(:beam4pm_ocel_events, %{id: id}, beam4pm_base_url: base_url)

      assert result.engine == :beam4pm
      assert [%{"id" => ^id, "attributes" => %{"activity" => "ash_ex4pm_chicago_integration_probe"}}] = result.value
    end

    test "reading conformance_result through the real dependency chain returns real, empty-but-valid state when nothing was seeded",
         %{base_url: base_url} do
      {:ok, result} = Beam4pm.execute(:beam4pm_conformance_results, %{}, beam4pm_base_url: base_url)

      assert result.engine == :beam4pm
      assert result.value == []
    end

    test "the real, currently-pinned ex4pm dependency (== 26.9.9) does not yet admit htn_plan/fond_policy -- honest canary, not an assumption" do
      # Real finding, checked directly against deps/ex4pm/lib/ex4pm/engine/beam4pm.ex's
      # actual @route_table rather than assumed: the published Hex release
      # this repo is pinned to predates BOTH the ferroplan_* individuals
      # and their rename to htn_plan/fond_policy -- only the two original
      # live ops exist in the deployed dependency today. This assertion
      # will start FAILING, on purpose, the moment the ex4pm pin is
      # bumped to a release carrying htn_plan/fond_policy and this test
      # is not yet updated -- surfacing the drift immediately.
      refute Beam4pm.supports?(:htn_plan, [])
      refute Beam4pm.supports?(:fond_policy, [])
      assert Beam4pm.supports?(:beam4pm_ocel_events, [])
      assert Beam4pm.supports?(:beam4pm_conformance_results, [])
    end
  end

  describe "AshEx4pm.AutomatedPlanning's honest current state (real function_exported?/3 checks, not a description)" do
    test "htn_plan/2 and fond_policy/2 do not exist yet, because this repo's ex4pm pin predates the ontology release carrying them" do
      refute function_exported?(AshEx4pm.AutomatedPlanning, :htn_plan, 2)
      refute function_exported?(AshEx4pm.AutomatedPlanning, :fond_policy, 2)
    end

    test "the module itself is real and compiles, just empty of delegate functions" do
      assert Code.ensure_loaded?(AshEx4pm.AutomatedPlanning)
      assert AshEx4pm.AutomatedPlanning.__info__(:functions) -- [module_info: 0, module_info: 1] == []
    end
  end
end
