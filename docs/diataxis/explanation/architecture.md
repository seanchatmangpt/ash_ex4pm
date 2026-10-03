# Explanation: AshEx4pm architecture

Why AshEx4pm looks the way it does: an ownership layering, a hard
distinction between admission and receipted DO, and an evidence pack
that is generated, not hand-written.

## The ownership layering

```
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
```

(from README.md). wasm4pm and ferroplan own algorithms and planning
semantics. ex4pm owns their runtime integration, admission, evidence,
replay, and provider boundaries. AshEx4pm owns only the Ash-facing
projection. Consequences:

- Every adapter module — `AshEx4pm.WasmRuntime`,
  `AshEx4pm.FerroplanRuntime`, `AshEx4pm.FerroplanSessions`,
  `AshEx4pm.EconomicISA` — declares a `@required_contract` of provider
  functions and refuses with a typed reason when the installed ex4pm
  does not export all of them (`lib/ash_ex4pm/wasm_runtime.ex`,
  `ferroplan_runtime.ex`, `ferroplan_sessions.ex`, `economic_isa.ex`).
  Standing is evidence-bounded (`standing/0` reads
  `Ex4pm.health(probe: false)` in the wasm case) — never assumed.
- `AshEx4pm.EconomicISA` deliberately owns no economic opcode registry:
  a second registry cannot emerge in the Ash layer
  (`lib/ash_ex4pm/economic_isa.ex` moduledoc).
- The ggen task generates from ex4pm's own packaged ontology
  (`Application.app_dir(:ex4pm, ...)`) instead of forking a copy,
  avoiding the two-repo-drift problem (`lib/mix/tasks/ash_ex4pm.ggen.sync.ex`).

## Projected is not ALIVE, is not authorized

The capability registry (`lib/ash_ex4pm/capabilities.ex`) records the
canonical owner, Ash projection, operation/arity, boundary
(`:observe | :inspect | :analyze | :construct | :admit | :do`), and
authority semantics for each projected capability. Its own moduledoc
states the invariant: existence in the registry means PROJECTED, not
ALIVE and not AUTHORIZED. `AshEx4pm.capability_standing/1` exists so
callers check live standing instead of inferring it from README or
registry presence.

This is also why plans, forecasts, statistics, and analysis results are
candidates only: `plan/4` and `plan_production/4` return data, they do
not mutate Ash business state and acquire no DO authority by crossing
the adapter (README, "Planning and session results are CONSTRUCT-side
candidates").

## Admission vs receipted DO

ex4pm's BRCE (`Ex4pm.Evidence.BRCE.execute/4,5`) is a boundary that
either refuses or runs a `fun`. AshEx4pm exposes two intentionally
different Ash changes over it:

1. `AshEx4pm.Changes.BrceGate` passes a pure placeholder
   (`fn -> :admitted end`) as the `fun` inside a prepended
   `before_action`. Its receipt proves admission, not the later Ash
   mutation — the DB write happens separately, after the hook returns.
2. `AshEx4pm.Changes.ReceiptedAction` installs an outermost
   `around_action` (prepended), so the real pipeline — before_action
   hooks, data-layer write, after_action hooks — runs *inside*
   `BRCE.execute/5`'s `fun`. The outcome receipt's `artifact_hash` is
   the digest of the real consequence term
   (`%{resource, action, primary_key, changed}`, built in
   `consequence_term/2` in `lib/ash_ex4pm/changes/receipted_action.ex`).
   A failed write becomes a `:blocked` outcome receipt, and idempotent
   replay re-serves a sealed result without re-running the mutation.

The remaining boundary, disclosed rather than hidden: the receipt is
sealed inside the `around_action` scope; a transactional commit failure
after that hook returns is not captured (README; CHANGELOG 26.10.2).

On the observation side the asymmetry is deliberate: the OCEL notifier
is post-commit and non-blocking — a refused ingest never rolls back the
already-committed Ash action, it is logged (`lib/ash_ex4pm/notifier.ex`,
`notify/1`). A *pre-commit* path is a different mechanism, and that is
`BrceGate`/`ReceiptedAction`.

## Events: what the notifier can and cannot see

The notifier receives one `Ash.Notifier.Notification` per
resource/changeset/action. Two disclosed limits
(`lib/ash_ex4pm/notifier.ex` moduledoc):

1. No cross-resource/cross-notification correlation — sibling
   resources' independent notifications are invisible to `notify/1`.
   This is a permanent constraint of the callback shape.
2. Relationships managed on the primary changeset ARE resolved:
   `build_envelope/2` reads the post-commit related records off
   `notification.data`, and declared `object_relationship` entities are
   proactively loaded via `Ash.Notifier.load/2`.

Fallback behavior is disclosed, not hidden: without a declared
`object_type`, the OCEL object type derives from the resource's module
name — a back-compat fallback that is the extension's biggest OCEL 2.0
nonconformance for non-opting resources (`AshEx4pm.Activity` moduledoc
in `lib/ash_ex4pm/dsl.ex`).

## The evidence pack is generated, not hand-written

26.10.3 vendors `ash-ex4pm-evidence-pack` from ggen-marketplace
(byte-identical copies of the ontology, 6 gates and 4 Tera templates,
all sha256-locked in `priv/ggen/vendor/PACKS.lock.json`; provenance in
`priv/ggen/vendor/provenance.ttl`) and renders a consumer pack at
`priv/ggen/vendor/render/ash-ex4pm-evidence-pack/` — the specimen
`MyApp.Fulfillment` emitter row replaced by this repo's real
`AshEx4pm.EngineRun` / `:conform` emitter. The rendered modules live in
`lib/ash_ex4pm/evidence/` (`AshEx4pm.Evidence.ProcessEvidence`,
`.Ex4pmAdapter`, `.RealtimeBridge`).

Two courts guard the invariants: the standalone
`test/ash_ex4pm/evidence_court.exs` (run `elixir test/ash_ex4pm/
evidence_court.exs` against the REAL ex4pm from `EX4PM_ROOT`) and the
mix-test court `test/ash_ex4pm/evidence_pack_test.exs` (same
invariants — fresh validates, digest stable, digest flips under tamper,
duplicate digest, malformed refused — against the pinned
`{:ex4pm, "== 26.10.1"}` hex dep).

One runner caveat, stated in `priv/ggen/manifest.json`: the hex
ggen_igniter dependency is EEx-only and must not actuate these Tera
`.tmpl` units; actuation uses the pinned ash_pplan ggen_igniter
toolchain. A legacy-EEx runner fails loudly rather than mis-rendering.

## Non-goals

From README.md: no global notifier injection (add `AshEx4pm.Notifier`
explicitly or rely on the transformer's simple-notifier persistence);
no automatic Reactor middleware injection; no treating a plan, forecast,
analysis result, or capability descriptor as execution authority; no
claiming ALIVE because code exists; no duplicating wasm4pm or ferroplan
semantic registries.

## Where to go next

- [Reference: Public API](../reference/api.md)
- [Tutorial: Emit OCEL events](../tutorials/emit-ocel-events-from-an-ash-resource.md)
- [How-to: Run a receipted Ash action](../how-to/run-a-receipted-ash-action.md)
