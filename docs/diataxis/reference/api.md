# Reference: AshEx4pm public API

Version 26.10.3. Every entry verified against `lib/`. Paths are
repo-relative to the ash_ex4pm checkout.

## Extension and registry (`lib/ash_ex4pm.ex`)

`AshEx4pm` is a `Spark.Dsl.Extension` (section `ex4pm`, transformer
`AshEx4pm.Transformers.Persist`, verifier `AshEx4pm.Verifiers.Verify`).

- `AshEx4pm.capabilities(filters \\ [])` — machine-readable capability
  projection registry (`AshEx4pm.Capabilities.all/1`). Filters, e.g.
  `AshEx4pm.capabilities(owner: :ferroplan)`.
- `AshEx4pm.capability(id)` — one descriptor by id, e.g.
  `AshEx4pm.capability(:ferroplan_plan)`.
- `AshEx4pm.capability_standing(id)` — evidence-bounded standing, e.g.
  `AshEx4pm.capability_standing(:wasm_algorithms)`.

Registry ids (`lib/ash_ex4pm/capabilities.ex`): `:ocel_event_emission`,
`:brce_admission`, `:receipted_action`, `:wasm_algorithms`,
`:wasm_statistics`, `:wasm_forecast`, `:ferroplan_plan`,
`:ferroplan_plan_production`, `:ferroplan_session_new`,
`:ferroplan_session_think`, `:ferroplan_session_replan_following`,
`:ferroplan_session_repair`, `:ferroplan_session_probe`,
`:capability_projection`, `:economic_isa_registry`. Existence in the
registry means PROJECTED, not ALIVE and not authorized.

## DSL (`lib/ash_ex4pm/dsl.ex`)

Section `ex4pm` (option `provenance_source`, default `:ash_ex4pm`,
tagged into each event's `metadata.source`).

- `activity :name, on: :action` — entity `AshEx4pm.Activity`. Options:
  `attributes:` (event-type schema, keyword of
  `{name, type}`; types `:string | :integer | :float | :boolean | :atom
  | :date | :datetime`), `object_type:` (must resolve to a declared
  `object_type` in the same section, else compile error),
  `qualifier` (default `"primary"`), `track_attribute_changes?:`
  (default `false`, update actions only), nested
  `object_relationship relationship, qualifier` entities
  (`AshEx4pm.ObjectRelationship`).
- `object_type :name, attributes: [...]` — entity `AshEx4pm.ObjectType`;
  object-attribute types additionally allow `:decimal`.
- Introspection (`lib/ash_ex4pm/info.ex`): `AshEx4pm.Info.compiled/1`,
  `compiled_result/1`, `compiled!/1`, `compiled?/1`, `activities/1`.

## Notifier (`lib/ash_ex4pm/notifier.ex`)

`AshEx4pm.Notifier` — emits an OCEL 2.0 envelope per action matching a
compiled `activity` declaration, through
`Ex4pm.Stream.Ingest.ingest_envelope/2`. Persisted into the resource's
`:simple_notifiers` by the transformer; explicit listing is redundant.
Post-commit, non-blocking: a refused ingest is logged, never raises the
action back.

Broadcaster app env `:ash_ex4pm, :broadcaster`: `nil` (default) | 1-arity
fun (`%{envelope:, log:, event_count:}`) | `{mod, fun, args}`. Fresh
ingest only; synchronous on the caller's process.

## BRCE changes (`lib/ash_ex4pm/changes/`)

- `AshEx4pm.Changes.BrceGate` — admission-only, prepended
  `before_action`; options `:operation` (required), `:authority_from`.
  Receipt in changeset context `:ash_ex4pm_brce_receipt`.
- `AshEx4pm.Changes.ReceiptedAction` — receipted DO, outermost
  prepended `around_action`; options `:operation` (required; `:local` =
  authority-free), `:idempotency_key`, `:expected_subject`,
  `:authority_from`, `:store`, `:evidence_store`. Helpers:
  `subject_hash/2`, `receipt/1`.
- `AshEx4pm.Errors.Refused` — refusals raised by `ReceiptedAction`
  (class `:forbidden`), reasons `{:authority_refused, code}`,
  `{:idempotency_conflict, key}`, `{:idempotency_in_flight, key}`,
  `{:stale_subject, expected, actual}`,
  `{:receipt_store_unavailable, store}`
  (`lib/ash_ex4pm/errors/refused.ex`).

## Analytical runs (`lib/ash_ex4pm/engine_run.ex`)

`AshEx4pm.EngineRun` — ETS-backed Ash resource (domain
`AshEx4pm.EngineRunDomain`). Create actions `:discover | :conform |
:simulate | :optimize | :plan` run the matching `Ex4pm` function via
`AshEx4pm.Changes.RunEngine` and persist the `%Ex4pm.Run{}` envelope
(arguments `:subject`, `:model`, `:problem`, `:engine_opts` as
applicable). Refusals (`%Ex4pm.Refusal{}`) raise
`AshEx4pm.Errors.Refused` and persist nothing. `read :by_receipt`
(argument `:receipt_hash`), generic `:replay` (wraps `Ex4pm.replay/2`)
and `:capabilities` (wraps `Ex4pm.capabilities/2`).

## Runtime seams

All seams own no semantics: they delegate to the ex4pm provider and
return typed refusals when the installed ex4pm lacks the required
contract. `provider/0`, `required_contract/0`, `missing_contract/0`,
`available?/0`, `standing/0` exist on every seam.

- `AshEx4pm.WasmRuntime` (`lib/ash_ex4pm/wasm_runtime.ex`) — provider
  `Ex4pm`. `health/1`, `algorithms/1`, `statistics/3`
  (`AshEx4pm.WasmRuntime.statistics(:mean, [1, 2, 3])`),
  `forecast/2` (`:method` of `:forecast | :holt | :ewma`),
  `ferroplan/3`. Refusal
  `{:wasm_runtime_unavailable, %{provider:, missing:}}`.
- `AshEx4pm.FerroplanRuntime` (`lib/ash_ex4pm/ferroplan_runtime.ex`) —
  provider `Ex4pm.Engine.Ferroplan`. `plan/4` (domain string, problem
  string, extra map, opts), `plan_production/4`, `readiness/1`. Refusal
  `{:ferroplan_runtime_unavailable, ...}`.
- `AshEx4pm.FerroplanSessions` (`lib/ash_ex4pm/ferroplan_sessions.ex`) —
  provider `Ex4pm.Engine.Ferroplan.Sessions`. `new/3`, `fork/2`,
  `free/1`, `recover/1`, `info/1` (strips `:handle` and `:transport`),
  `list/0`, `think/2`, `repair/2`, `replan_following/2`,
  `probe/3` (id, candidates, opts), `observe/2`, `suffix/1`,
  `advance/1`, `goal_met?/1`, `plan_valid?/1`, `call/4`,
  `ensure_started/0`, `ops/0`. Refusal
  `{:ferroplan_session_runtime_unavailable, ...}`.
- `AshEx4pm.EconomicISA` (`lib/ash_ex4pm/economic_isa.ex`) — provider
  `Ex4pm.EconomicISA`. `registry/0`, `ranges/0`, `unknown/0`,
  `escape/0`, `lookup_byte/1`, `lookup_activity/1`, `category/1`,
  `encode/1` (`{:extended, semantic_id}` uses the escape record),
  `decode/1`, `to_event/4`, `project/1`. Refusal
  `{:economic_isa_unavailable, ...}`.

## Evidence pack (`lib/ash_ex4pm/evidence/`)

Rendered by the vendored ggen pack `ash-ex4pm-evidence-pack`
(`priv/ggen/vendor/`, locked in `priv/ggen/vendor/PACKS.lock.json`;
emitter row `AshEx4pm.EngineRun` / `:conform`, namespace
`AshEx4pm.Evidence`).

- `AshEx4pm.Evidence.ProcessEvidence` — `events_from_receipt/3`
  (receipt, subject, opts `:tasks`, `:realizations`, `:failed_task`,
  `:run_prefix`) producing `task_attempted` / `task_succeeded` /
  `task_failed` `AshEx4pm.Evidence.ProcessEvidence.Event` structs;
  `export/2` (`:ocel2_json`, needs Jason),
  `digest/1` (tamper-evident sha256).
- `AshEx4pm.Evidence.Ex4pmAdapter` — `available?/0`, `envelope/2`,
  `validate/2` (real `Ex4pm.OCEL.validate_envelope/1`), `ingest/2`
  (real `Ex4pm.Stream.Ingest.ingest_envelope/2` + opt-in broadcaster via
  app env `:ash_ex4pm, :broadcaster`), `activities/1`. With ex4pm
  absent: `{:error, %{reason: :unsupported, detail: :ex4pm_not_available}}`.
- `AshEx4pm.Evidence.RealtimeBridge` — GenServer seam;
  `start_link/1` (opt `:capacity`, default app env
  `:ash_ex4pm, :bridge_capacity` else 10_000), `push/1`,
  `drain/0` (oldest-first, clears), `size/0`, `capacity/0`. Drop-oldest
  overflow, 50 ms tick.
- `AshEx4pm.CallLogBridge` (`lib/ash_ex4pm/call_log_bridge.ex`) —
  bridges `Ex4pm.Engine.CallLog` telemetry into ingest; `start_link/1`
  (opts `:name`, `:limit` default 100), `calls/1`, `stats/1`,
  `store/1`, `correlate/2`, `ingest/2`. Not started automatically.

## Receipt stores (`lib/ash_ex4pm/receipt_store.ex`, `receipt_store/ets.ex`)

`AshEx4pm.ReceiptStore` behaviour: `reserve/2`, `seal/2`, `release/1`.
Built-in `AshEx4pm.ReceiptStore.Ets` (GenServer, named public ETS
table, atomic `:ets.insert_new/2` reservation). Add to a supervision
tree; when down, callbacks return
`{:error, :receipt_store_unavailable}`.

## Calculations, run-engine change, errors

- `AshEx4pm.Changes.RunEngine` (`lib/ash_ex4pm/changes/run_engine.ex`) —
  option `:operation` in `:discover | :conform | :simulate | :optimize |
  :plan`; CONSTRUCT-only, no BRCE/DO path.
- `AshEx4pm.Errors.Refused` (`lib/ash_ex4pm/errors/refused.ex`) —
  `Splode.Error`, class `:forbidden`, fields `:reason`, `:refusal`.

## Mix task (`lib/mix/tasks/ash_ex4pm.ggen.sync.ex`)

`mix ash_ex4pm.ggen.sync [--manifest path] [--unit name]` — runs every
ggen_igniter unit in `priv/ggen/manifest.json`, resolving each unit's
`"{{ex4pm_ontology}}"` placeholder to ex4pm's packaged
`priv/ontology/ex4pm.ttl` via `Application.app_dir(:ex4pm, ...)`. The
hex ggen_igniter dep is EEx-only: the vendored Tera `.tmpl` units must
be actuated by the pinned ash_pplan ggen_igniter toolchain
(`priv/ggen/manifest.json` caveat).
