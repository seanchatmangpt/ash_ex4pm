defmodule AshEx4pm.FerroplanRuntime do
  @moduledoc """
  Ash-facing adapter over `Ex4pm.Engine.Ferroplan`, the canonical ferroplan
  runtime that ex4pm owns.

  ex4pm must carry the runtime itself, not forward-declared route stubs: the
  generated `AshEx4pm.Ferroplan` routes go through `Ex4pm.Engine.Beam4pm`, whose
  ferroplan routes are still `forward_declared` (typed `:beam4pm_route_not_live`).
  This module is the live path.  It owns no planner semantics; it delegates to
  the ex4pm provider once the installed ex4pm exports the full contract, and
  until then every call is a typed `:ferroplan_runtime_unavailable` refusal with
  standing `:partial_alive`.  The contract mirrors the operation surface of the
  existing wasm-backed planner in `~/beam4pm` (`BeamPM.Ferroplan`) so that
  runtime can be ported into ex4pm unchanged.

  Plans are candidates only.  This adapter grants no DO authority.
  """

  @provider Ex4pm.Engine.Ferroplan

  @required_contract [plan: 4, plan_production: 4, readiness: 1, version: 1]

  @type refusal :: {:ferroplan_runtime_unavailable, map()}

  @doc "Canonical provider module (owned by ex4pm)."
  @spec provider() :: module()
  def provider, do: @provider

  @doc "Provider surface this adapter requires."
  @spec required_contract() :: keyword(non_neg_integer())
  def required_contract, do: @required_contract

  @doc "Required provider functions that are not exported (empty when fully available)."
  @spec missing_contract() :: keyword(non_neg_integer())
  def missing_contract do
    if Code.ensure_loaded?(@provider) do
      Enum.reject(@required_contract, fn {name, arity} ->
        function_exported?(@provider, name, arity)
      end)
    else
      @required_contract
    end
  end

  @doc "True when ex4pm's ferroplan runtime exports the full required contract."
  @spec available?() :: boolean()
  def available?, do: missing_contract() == []

  @doc "Evidence-bounded standing; wasm artifact presence is reported, never assumed."
  @spec standing() :: {:alive | :partial_alive, map()}
  def standing do
    if available?() do
      {:alive, %{provider: @provider, wasm_built?: apply(@provider, :wasm_built?, [])}}
    else
      {:partial_alive, %{provider: @provider, missing: missing_contract()}}
    end
  end

  @doc "Classical solve (`Ex4pm.Engine.Ferroplan.plan/4`)."
  @spec plan(String.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def plan(domain, problem, extra \\ %{}, opts \\ []) do
    with_provider(fn -> apply(@provider, :plan, [domain, problem, extra, opts]) end)
  end

  @doc "Bounded, candidate-only production solve (`Ex4pm.Engine.Ferroplan.plan_production/4`)."
  @spec plan_production(String.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def plan_production(domain, problem, extra \\ %{}, opts \\ []) do
    with_provider(fn -> apply(@provider, :plan_production, [domain, problem, extra, opts]) end)
  end

  @doc "Engine capability manifest and fingerprint."
  @spec readiness(keyword()) :: {:ok, map()} | {:error, term()}
  def readiness(opts \\ []), do: with_provider(fn -> apply(@provider, :readiness, [opts]) end)

  defp with_provider(fun) do
    if available?() do
      fun.()
    else
      {:error,
       {:ferroplan_runtime_unavailable, %{provider: @provider, missing: missing_contract()}}}
    end
  end
end
