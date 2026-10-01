# AshEx4pm

AshEx4pm is the Ash projection layer for ex4pm process evidence, admitted
runtime capabilities, wasm4pm analysis, ferroplan planning, and receipted Ash
actions.

The ownership boundary is deliberate:

~~~text
Ash resource/domain
        |
        v
    AshEx4pm
        |
        v
      ex4pm
       /  \
      v    v
 wasm4pm  ferroplan
~~~

wasm4pm and ferroplan own algorithms and planning semantics. ex4pm owns their
runtime integration, admission, evidence, replay, and provider boundaries.
AshEx4pm owns the Ash-facing projection. A capability being known or projected
does not mean it is ALIVE, authorized, or allowed to perform DO.

## Installation

~~~elixir
def deps do
  [
    {:ash_ex4pm, "~> 26.10"}
  ]
end
~~~

AshEx4pm 26.10.2 continues to pin the published ex4pm 26.10.1 contract exactly:

~~~elixir
{:ex4pm, "== 26.10.1"}
~~~

The patch component of ex4pm's CalVer is contract-bearing, so this project does
not widen or invent compatibility with an unverified upstream release.

## Documentation

The README is the entrypoint, not the full manual. Start with the
[Diátaxis index](docs/INDEX.md).

Canonical upstream documentation:

- [ex4pm Diátaxis reference](https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md)
- [wasm4pm Diátaxis index](https://github.com/seanchatmangpt/wasm4pm/blob/main/docs/INDEX.md)
- [ferroplan planning types](https://github.com/seanchatmangpt/ferroplan/blob/main/docs/planning-types.md)
- [ferroplan FOND/HDDL semantics](https://github.com/seanchatmangpt/ferroplan/blob/main/docs/FOND-HTN.md)

## Minimal OCEL resource

Declare an ex4pm DSL block and explicitly register the notifier:

~~~elixir
defmodule MyApp.Order do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [AshEx4pm.Notifier],
    extensions: [AshEx4pm]

  ex4pm do
    activity(:order_created, on: :create)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:status])
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:status, :atom, default: :pending, public?: true)
  end
end
~~~

A matching post-commit notification builds an OCEL 2.0 envelope and delegates
to Ex4pm.Stream.Ingest.ingest_envelope/1. A refused ingest does not roll back the
already-committed Ash action.

## Capability discovery

v26.10.2 adds a machine-readable projection registry:

~~~elixir
AshEx4pm.capabilities()
AshEx4pm.capabilities(owner: :ferroplan)
AshEx4pm.capability(:ferroplan_plan)
AshEx4pm.capability_standing(:wasm_algorithms)
~~~

The important distinction is:

~~~text
upstream capability
    != projected capability
    != admitted runtime capability
    != authorized consequence
~~~

The registry records the canonical owner, Ash projection, function/arity,
boundary, authority semantics, DO authority, and documentation for each
projected capability. See [Capability reference](docs/reference/capabilities.md).

## wasm4pm through AshEx4pm.WasmRuntime

AshEx4pm.WasmRuntime delegates to ex4pm's canonical wasm runtime surface. It
owns no wasm4pm semantics.

Representative calls:

~~~elixir
AshEx4pm.WasmRuntime.available?()
AshEx4pm.WasmRuntime.standing()
AshEx4pm.WasmRuntime.algorithms()
AshEx4pm.WasmRuntime.statistics(:mean, [1, 2, 3])
AshEx4pm.WasmRuntime.forecast([1, 2, 3])
~~~

The wider wasm4pm substrate includes process mining, object-centric querying,
statistics, forecasting, deterministic cognition and planning. Upstream
existence does not imply that every capability is projected or ALIVE here; use
the registry and live standing surfaces rather than README inference.

## ferroplan through AshEx4pm

The stateless planning seam is AshEx4pm.FerroplanRuntime:

~~~elixir
AshEx4pm.FerroplanRuntime.available?()
AshEx4pm.FerroplanRuntime.standing()
AshEx4pm.FerroplanRuntime.plan(domain, problem)
AshEx4pm.FerroplanRuntime.plan_production(domain, problem)
~~~

The stateful seam is AshEx4pm.FerroplanSessions:

~~~elixir
{:ok, session} = AshEx4pm.FerroplanSessions.new(domain, problem)
AshEx4pm.FerroplanSessions.observe(session.id, observation)
AshEx4pm.FerroplanSessions.think(session.id)
AshEx4pm.FerroplanSessions.replan_following(session.id)
AshEx4pm.FerroplanSessions.repair(session.id)
~~~

Planning and session results are CONSTRUCT-side candidates. They do not mutate
Ash business state and do not acquire DO authority by crossing the adapter.

## BRCE: admission-only and receipted DO are separate

AshEx4pm exposes two intentionally different changes.

### Admission-only: AshEx4pm.Changes.BrceGate

~~~elixir
create :create do
  change({AshEx4pm.Changes.BrceGate, operation: :create_order})
end
~~~

BrceGate performs pre-action admission with a pure placeholder callback. Its
receipt proves admission, not the later Ash mutation. Use this when admission
alone is the required boundary.

### Receipted DO: AshEx4pm.Changes.ReceiptedAction

~~~elixir
create :create do
  change({AshEx4pm.Changes.ReceiptedAction, operation: :create_order})
end
~~~

ReceiptedAction installs an outermost around_action and runs the real Ash
mutation inside Ex4pm.Evidence.BRCE.execute/5. The outcome receipt binds the
real consequence digest, and the returned Ash record carries
ash_ex4pm_receipt metadata. It also supports subject checks and idempotency.

The remaining boundary is narrower: the receipt is sealed inside the
around_action transaction scope. A transactional commit failure after that hook
returns is not yet captured and remains unverified for transactional data
layers.

For update/destroy actions using ReceiptedAction, follow the module contract and
set require_atomic? false.

## Capability boundaries

The public capability graph currently includes:

- OCEL 2.0 event emission and object relationships;
- BRCE admission-only gating;
- BRCE-wrapped receipted Ash DO;
- wasm4pm algorithm discovery, statistics and forecasting through ex4pm;
- ferroplan stateless planning and production planning;
- stateful ferroplan sessions for think, repair, probe and replanning;
- Ex4pm.Engine.Result projection into Ash-friendly evidence;
- the canonical economic ISA adapter.

No alternate wasm or planner semantics are implemented in AshEx4pm.

## Non-goals

- Global notifier injection: add AshEx4pm.Notifier explicitly.
- Automatic Reactor middleware injection.
- Treating a plan, forecast, analysis result, or capability descriptor as
  execution authority.
- Claiming ALIVE solely because code or an upstream algorithm exists.
- Duplicating wasm4pm or ferroplan semantic registries.

## Verification

The repository CI runs mix verify: formatting, warnings-as-errors compilation,
and the real test suite. v26.10.2 also tests the capability registry for unique
IDs, real exported projection functions, documentation coverage, and the
planner/DO separation.

## License

MIT
