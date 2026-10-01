defmodule AshEx4pm.FerroplanSessions do
  @moduledoc """
  Ash-facing seam over `Ex4pm.Engine.Ferroplan.Sessions`, ex4pm's stateful
  ferroplan session facade (one wasm instance per session).

  Mirrors `AshEx4pm.FerroplanRuntime`: it owns no planner semantics, delegates to
  the ex4pm provider, and if the installed ex4pm lacks the contract every call is
  a typed `:ferroplan_session_runtime_unavailable` refusal.  `info/1` strips the
  opaque guest `:handle` and the `:transport` pid.

  Session ops are CONSTRUCT-only candidates; this adapter grants no DO authority.
  """

  @provider Ex4pm.Engine.Ferroplan.Sessions
  @session Ex4pm.Engine.Ferroplan.Session

  @required_contract [
    new: 3,
    fork: 2,
    free: 1,
    recover: 1,
    info: 1,
    list: 0,
    call: 4,
    think: 2,
    repair: 2,
    replan_following: 2,
    probe: 3,
    observe: 2,
    suffix: 1,
    advance: 1,
    goal_met?: 1,
    plan_valid?: 1,
    ensure_started: 0
  ]

  @type refusal :: {:ferroplan_session_runtime_unavailable, map()}

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

  @doc "True when ex4pm's session facade exports the full required contract."
  @spec available?() :: boolean()
  def available?, do: missing_contract() == []

  @doc "Evidence-bounded standing."
  @spec standing() :: {:alive | :partial_alive, map()}
  def standing do
    if available?() do
      {:alive, %{provider: @provider, ops: length(ops())}}
    else
      {:partial_alive, %{provider: @provider, missing: missing_contract()}}
    end
  end

  @doc "All session op names (without the `session_` prefix), from the ex4pm session process."
  @spec ops() :: [String.t()]
  def ops, do: apply(@session, :ops, [])

  @doc "Idempotently ensure the session supervision tree is running."
  def ensure_started, do: with_provider(fn -> apply(@provider, :ensure_started, []) end)

  @doc "Create a session on PDDL domain/problem."
  def new(domain, problem, opts \\ []),
    do: with_provider(fn -> apply(@provider, :new, [domain, problem, opts]) end)

  @doc "Fork into an independent session."
  def fork(session_id, opts \\ []),
    do: with_provider(fn -> apply(@provider, :fork, [session_id, opts]) end)

  @doc "Free a session."
  def free(session_id), do: with_provider(fn -> apply(@provider, :free, [session_id]) end)

  @doc "Rebuild a session whose wasm instance died; returns info without the handle."
  def recover(session_id) do
    with_provider(fn ->
      case apply(@provider, :recover, [session_id]) do
        {:ok, info} -> {:ok, strip(info)}
        other -> other
      end
    end)
  end

  @doc "Diagnostic info with `:handle` and `:transport` stripped."
  def info(session_id) do
    with_provider(fn ->
      case apply(@provider, :info, [session_id]) do
        {:ok, info} -> {:ok, strip(info)}
        other -> other
      end
    end)
  end

  @doc "Ids of live sessions."
  def list, do: with_provider(fn -> {:ok, apply(@provider, :list, [])} end)

  def think(id, opts \\ []), do: delegate(:think, [id, opts])
  def repair(id, opts \\ []), do: delegate(:repair, [id, opts])
  def replan_following(id, opts \\ []), do: delegate(:replan_following, [id, opts])
  def probe(id, candidates, opts \\ []), do: delegate(:probe, [id, candidates, opts])
  def observe(id, sight), do: delegate(:observe, [id, sight])
  def suffix(id), do: delegate(:suffix, [id])
  def advance(id), do: delegate(:advance, [id])
  def goal_met?(id), do: delegate(:goal_met?, [id])
  def plan_valid?(id), do: delegate(:plan_valid?, [id])

  @doc "Generic session op."
  def call(id, op, args \\ %{}, opts \\ []), do: delegate(:call, [id, op, args, opts])

  defp delegate(fun, args), do: with_provider(fn -> apply(@provider, fun, args) end)

  defp strip(info), do: Map.drop(info, [:handle, :transport])

  defp with_provider(fun) do
    if available?() do
      fun.()
    else
      {:error,
       {:ferroplan_session_runtime_unavailable,
        %{provider: @provider, missing: missing_contract()}}}
    end
  end
end
