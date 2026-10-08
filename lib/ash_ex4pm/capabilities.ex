defmodule AshEx4pm.Capabilities do
  @moduledoc """
  Canonical registry for the capability surface projected by AshEx4pm.

  This is a projection registry, not a second semantic registry. wasm4pm and
  ferroplan own their algorithms; ex4pm owns admitted runtime integration;
  AshEx4pm describes the Ash-facing seam.

  Existence in this registry means PROJECTED, not ALIVE and not AUTHORIZED.
  """

  alias AshEx4pm.Capability

  @base_docs %{
    index: "docs/INDEX.md",
    reference: "docs/diataxis/reference/api.md",
    explanation: "docs/diataxis/explanation/architecture.md"
  }

  @wasm_docs "https://github.com/seanchatmangpt/wasm4pm/blob/main/docs/INDEX.md"
  @ferroplan_docs "https://github.com/seanchatmangpt/ferroplan/blob/main/docs/planning-types.md"
  @ex4pm_docs "https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md"

  @capabilities [
    %Capability{
      id: :ocel_event_emission,
      category: :process_evidence,
      owner: :ash_ex4pm,
      projection: AshEx4pm.Notifier,
      operation: :notify,
      arity: 1,
      boundary: :observe,
      authority: :none,
      do_authority?: false,
      standing: nil,
      docs: Map.put(@base_docs, :upstream, @ex4pm_docs)
    },
    %Capability{
      id: :brce_admission,
      category: :admission,
      owner: :ex4pm,
      projection: AshEx4pm.Changes.BrceGate,
      operation: :change,
      arity: 3,
      boundary: :admit,
      authority: :required,
      do_authority?: false,
      standing: nil,
      docs: Map.put(@base_docs, :upstream, @ex4pm_docs)
    },
    %Capability{
      id: :receipted_action,
      category: :actuation,
      owner: :ex4pm,
      projection: AshEx4pm.Changes.ReceiptedAction,
      operation: :change,
      arity: 3,
      boundary: :do,
      authority: :operation_dependent,
      do_authority?: true,
      standing: nil,
      docs: Map.put(@base_docs, :upstream, @ex4pm_docs)
    },
    %Capability{
      id: :wasm_algorithms,
      category: :process_intelligence,
      owner: :wasm4pm,
      projection: AshEx4pm.WasmRuntime,
      operation: :algorithms,
      arity: 1,
      boundary: :inspect,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.WasmRuntime, :standing, []},
      docs: Map.put(@base_docs, :upstream, @wasm_docs)
    },
    %Capability{
      id: :wasm_statistics,
      category: :process_intelligence,
      owner: :wasm4pm,
      projection: AshEx4pm.WasmRuntime,
      operation: :statistics,
      arity: 3,
      boundary: :analyze,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.WasmRuntime, :standing, []},
      docs: Map.put(@base_docs, :upstream, @wasm_docs)
    },
    %Capability{
      id: :wasm_forecast,
      category: :process_intelligence,
      owner: :wasm4pm,
      projection: AshEx4pm.WasmRuntime,
      operation: :forecast,
      arity: 2,
      boundary: :analyze,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.WasmRuntime, :standing, []},
      docs: Map.put(@base_docs, :upstream, @wasm_docs)
    },
    %Capability{
      id: :ferroplan_plan,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanRuntime,
      operation: :plan,
      arity: 4,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanRuntime, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :ferroplan_plan_production,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanRuntime,
      operation: :plan_production,
      arity: 4,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanRuntime, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :ferroplan_session_new,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanSessions,
      operation: :new,
      arity: 3,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanSessions, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :ferroplan_session_think,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanSessions,
      operation: :think,
      arity: 2,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanSessions, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :ferroplan_session_replan_following,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanSessions,
      operation: :replan_following,
      arity: 2,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanSessions, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :ferroplan_session_repair,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanSessions,
      operation: :repair,
      arity: 2,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanSessions, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :ferroplan_session_probe,
      category: :planning,
      owner: :ferroplan,
      projection: AshEx4pm.FerroplanSessions,
      operation: :probe,
      arity: 3,
      boundary: :construct,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.FerroplanSessions, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ferroplan_docs)
    },
    %Capability{
      id: :capability_projection,
      category: :evidence,
      owner: :ex4pm,
      projection: AshEx4pm.CapabilityProjection,
      operation: :project,
      arity: 3,
      boundary: :inspect,
      authority: :none,
      do_authority?: false,
      standing: nil,
      docs: Map.put(@base_docs, :upstream, @ex4pm_docs)
    },
    %Capability{
      id: :economic_isa_registry,
      category: :semantic_projection,
      owner: :ex4pm,
      projection: AshEx4pm.EconomicISA,
      operation: :registry,
      arity: 0,
      boundary: :inspect,
      authority: :none,
      do_authority?: false,
      standing: {AshEx4pm.EconomicISA, :standing, []},
      docs: Map.put(@base_docs, :upstream, @ex4pm_docs)
    }
  ]

  @doc "Returns all projected capabilities, optionally filtered by descriptor fields."
  @spec all(keyword()) :: [Capability.t()]
  def all(filters \\ []) when is_list(filters) do
    Enum.filter(@capabilities, fn capability ->
      Enum.all?(filters, fn {key, value} -> Map.get(capability, key) == value end)
    end)
  end

  @doc "Looks up one capability by id."
  @spec get(atom()) :: {:ok, Capability.t()} | {:error, :unknown_capability}
  def get(id) when is_atom(id) do
    case Enum.find(@capabilities, &(&1.id == id)) do
      nil -> {:error, :unknown_capability}
      capability -> {:ok, capability}
    end
  end

  @doc "Checks whether the Ash-facing projection function is present."
  @spec available?(atom() | Capability.t()) :: boolean()
  def available?(id) when is_atom(id) do
    case get(id) do
      {:ok, capability} -> available?(capability)
      {:error, :unknown_capability} -> false
    end
  end

  def available?(%Capability{} = capability) do
    Code.ensure_loaded?(capability.projection) and
      function_exported?(capability.projection, capability.operation, capability.arity)
  end

  @doc """
  Returns evidence-bounded runtime standing when a projection exposes an
  inspection-only standing callback. Capabilities without such a callback
  remain PROJECTED instead of being promoted to ALIVE.
  """
  @spec standing(atom() | Capability.t()) ::
          {:projected, map()} | {:error, :unknown_capability} | term()
  def standing(id) when is_atom(id) do
    case get(id) do
      {:ok, capability} -> standing(capability)
      {:error, :unknown_capability} = error -> error
    end
  end

  def standing(%Capability{standing: nil} = capability) do
    {:projected, %{capability: capability.id, reason: :no_runtime_probe}}
  end

  def standing(%Capability{standing: {module, function, args}} = capability) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      {:partial_alive,
       %{capability: capability.id, reason: :standing_provider_unavailable, provider: module}}
    end
  end
end
