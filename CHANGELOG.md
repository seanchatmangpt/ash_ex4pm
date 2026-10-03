# Changelog

All notable changes to `ash_ex4pm` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [26.10.3] - 2026-10-02

### Added

- **Vendored `ash-ex4pm-evidence-pack`** from ggen-marketplace (main @
  `e8e2c3066e7404d097cb21083d05e6814f9a3dcc`, lock:
  `priv/ggen/vendor/PACKS.lock.json`, provenance:
  `priv/ggen/vendor/provenance.ttl`), following ex4pm's file-level vendoring
  pattern (`~/ex4pm/priv/ggen/vendor/sync.sh`), adapted deterministically in
  `priv/ggen/vendor/sync.sh`:
  - byte-identical vendored copies of the pack's ontology, 6 gates and
    4 Tera templates (all sha256-locked);
  - a consumer render-pack at `priv/ggen/vendor/render/ash-ex4pm-evidence-pack/`:
    the specimen `MyApp.Fulfillment` Emitter row replaced by this repo's real
    `AshEx4pm.EngineRun` / `:conform` emitter (namespace `AshEx4pm.Evidence`,
    app `:ash_ex4pm`), and the D6 specimen output paths rewritten to
    `lib/ash_ex4pm/evidence/` + `test/ash_ex4pm/`.
- **Rendered evidence surface** (`lib/ash_ex4pm/evidence/`, modules
  `AshEx4pm.Evidence.*`, rendered via ggen_igniter 0abed8a's reactor
  pipeline, 1 Emitter row fan-out each):
  - `AshEx4pm.Evidence.ProcessEvidence` (+ `.Event`): receipts ->
    task_attempted / task_succeeded / task_failed OCEL events, pure OCEL 2.0
    JSON export, tamper-evident sha256 content digest;
  - `AshEx4pm.Evidence.Ex4pmAdapter`: guarded `ash_ex4pm/1` wire envelope
    (validate via real `Ex4pm.OCEL.validate_envelope/1`, ingest via real
    `Ex4pm.Stream.Ingest.ingest_envelope/2`, opt-in broadcaster via app env
    `:ash_ex4pm, :broadcaster`); degrades to
    `{:error, %{reason: :unsupported, detail: :ex4pm_not_available}}` with
    ex4pm absent;
  - `AshEx4pm.Evidence.RealtimeBridge`: bounded persistent_term -> ETS
    ring-buffer seam (capacity via `:ash_ex4pm, :bridge_capacity`, default
    10_000, drop-oldest overflow).
- **Evidence courts**: the rendered standalone court
  `test/ash_ex4pm/evidence_court.exs` (`elixir test/ash_ex4pm/evidence_court.exs`,
  5 PASS: fresh validates / digest stable / digest flips under tamper /
  duplicate digest / malformed refused -- against the REAL Ex4pm compiled
  from `EX4PM_ROOT`), plus the mix-test court
  `test/ash_ex4pm/evidence_pack_test.exs` (same invariants against the real
  `{:ex4pm, "== 26.10.1"}` hex dep).
- **`priv/ggen/manifest.json`** now lists the vendored pack (was `[]`):
  source git sha, lock path, per-template -> output mapping, test path, and
  the runner caveat: `mix ash_ex4pm.ggen.sync`'s hex ggen_igniter dep is
  EEx-only and must NOT actuate these Tera `.tmpl` units; actuation runs via
  the pinned ash_pplan ggen_igniter (`0abed8a`) toolchain. A legacy-EEx
  runner would fail loudly (no template/out keys match its unit schema)
  rather than mis-render.

### Changed

- `mix test` now also covers the evidence pack invariants via
  `test/ash_ex4pm/evidence_pack_test.exs`.

## [26.10.2] - 2026-10-01

### Added

- **Optional realtime broadcaster** via app env
  `Application.get_env(:ash_ex4pm, :broadcaster)` — `nil` (default, current
  behavior unchanged), a 1-arity fun, or `{module, function, args}`. Threaded
  through `AshEx4pm.Notifier.notify/1` into
  `Ex4pm.Stream.Ingest.ingest_envelope/2`'s existing `:broadcaster` opt.
  Fire-and-forget, fresh-ingest-only. A crashing broadcaster raises
  synchronously out of the action as `Ash.Error.Unknown` (stored receipts
  survive). Test coverage: `test/ash_ex4pm/broadcaster_test.exs`.
Documentation and capability-surface release. No new wasm4pm or ferroplan
semantics are implemented in AshEx4pm.

### Added

- AshEx4pm.Capability and AshEx4pm.Capabilities: a machine-readable projection
  registry recording semantic owner, Ash projection, operation/arity,
  OBSERVE/ANALYZE/CONSTRUCT/ADMIT/DO boundary, authority semantics,
  consequential-DO capability, optional inspection-only standing probe, and
  canonical documentation.
- Public AshEx4pm.capabilities/1, capability/1 and capability_standing/1.
- Federated Diátaxis index plus tutorial, how-to, reference and explanation
  entrypoints that route to canonical ex4pm, wasm4pm and ferroplan docs.
- Registry courts for unique IDs, real exported projections, documentation
  coverage, and planning/DO separation.

### Changed

- README now represents the already-shipped WasmRuntime, FerroplanRuntime and
  FerroplanSessions surfaces instead of presenting the package as only an OCEL
  notifier plus admission gate.
- Corrected the stale BRCE scope statement: BrceGate remains admission-only,
  while ReceiptedAction already runs the real Ash mutation inside
  Ex4pm.Evidence.BRCE.execute/5 and binds the consequence to the outcome
  receipt. The remaining unverified boundary is transactional commit failure
  after around_action returns.
- Package version bumped to 26.10.2. The exact published ex4pm 26.10.1 pin is
  intentionally unchanged; this release does not invent compatibility with an
  unverified upstream contract.

## [26.10.1] - 2026-10-01

Release aligned with `ex4pm` 26.10.1 — the published Hex release that removes
all beam4pm knowledge from `ex4pm` (ex4pm `2fd3a21`): `Ex4pm.Engine.Beam4pm`
no longer exists upstream. Folds all previously-unreleased work since 26.9.10.

### Added

- **Live ex4pm runtime seams** (new modules; each owns no semantics, delegates
  to its ex4pm provider, and refuses typed when the installed ex4pm lacks the
  required contract — candidates only, no DO authority):
  - `AshEx4pm.WasmRuntime` — Ash-facing adapter over ex4pm's bundled wasm
    engines (wasm4pm statistics, forecasting, and ferroplan); every call on a
    missing contract is a typed `:wasm_runtime_unavailable` refusal with
    standing `:partial_alive`; `standing/0` is evidence-bounded from
    `Ex4pm.health(probe: false)`.
  - `AshEx4pm.FerroplanRuntime` — the live planning path over
    `Ex4pm.Engine.Ferroplan`; typed `:ferroplan_runtime_unavailable` refusals.
  - `AshEx4pm.FerroplanSessions` — seam over `Ex4pm.Engine.Ferroplan.Sessions`,
    ex4pm's stateful ferroplan session facade (one wasm instance per session);
    typed `:ferroplan_session_runtime_unavailable` refusals; `info/1` strips
    the opaque guest `:handle` and the `:transport` pid.
  - `AshEx4pm.CallLogBridge` — GenServer bridging `Ex4pm.Engine.CallLog` into
    an Ash-side process: subscribes to the call log, attaches a
    `[:ex4pm, :engine, :call, :stop]` telemetry handler, ingests each envelope
    through `Ex4pm.Stream.Ingest.ingest_envelope/2` into its own evidence
    store (call-log sequence numbers are VM-global, so the bridge keeps its
    own sequence space), and retains the last `:limit` call summaries; a
    refused or failed ingestion is recorded in `stats/1` and never crashes
    the bridge.
  - `AshEx4pm.CapabilityProjection` — flat, storable projection of an
    `Ex4pm.Engine.Result` (or typed refusal); `admitted` is true only when
    standing is `:alive`, the wasm replay was verified, the artifact sha256 is
    a binary, and the transport identity was observed. Everything else is a
    projection, never authority.
- **`AshEx4pm.EngineRun` + `AshEx4pm.EngineRunDomain` +
  `AshEx4pm.Changes.RunEngine` + `AshEx4pm.Calculations`** — an ETS-backed Ash
  resource recording one real ex4pm analytical run per create action
  (`:discover | :conform | :simulate | :optimize | :plan`) through the
  CONSTRUCT-only `RunEngine` change, persisting the resulting `%Ex4pm.Run{}`
  envelope; refusals raise `AshEx4pm.Errors.Refused` and persist nothing;
  `:by_receipt` reads by outcome receipt hash, and generic `:replay` /
  `:capabilities` actions wrap `Ex4pm.replay/2` and `Ex4pm.capabilities/2`.
  Calculations: `AshEx4pm.Calculations.Statistic` and
  `.Forecast` run a real wasm4pm statistic / forecast over a numeric-array
  attribute (the run's `value`, or `nil` on refusal); `.CapabilityProjection`
  derives `admitted` from stored projection fields without re-executing the
  engine.
- **CI workflow** (d2c9e0c, upgraded by 0a7f44b): `mix verify` (`format
  --check-formatted`, `compile --warnings-as-errors`, `test`) on push to
  `main` and on every `pull_request`, OTP 27.1 / Elixir 1.17.3 on
  `ubuntu-24.04`, with dep/build caching keyed on `mix.lock`. All
  dependencies resolve from Hex per `mix.lock` (no git or path deps), so CI
  verifies the same dependency closure a consumer receives.
- **`Ash.Notifier.load/2` implementation** (d4ffb71): `AshEx4pm.Notifier`
  implements Ash 3.x's optional notifier `load/2` callback, proactively
  loading declared `object_relationship` targets that the triggering action
  did not already select/load, so they are no longer silently omitted from
  the emitted OCEL envelope.
- **`AshEx4pm.Changes.ReceiptedAction`** (f1adb10): outermost `around_action`
  running the whole in-transaction pipeline (before_action hooks, data-layer
  write, after_action hooks) as `Ex4pm.Evidence.BRCE.execute/5`'s fun, so the
  outcome receipt's `artifact_hash` is the sha256 of the real consequence
  (resource, action, primary key, changed attributes); a failed write yields a
  `:blocked` outcome receipt. Adds `idempotency_key` (same key + fingerprint
  returns the sealed result as `:known_replay` without mutating; a different
  fingerprint is refused `{:idempotency_conflict, key}`), `expected_subject`
  (mismatch refused `{:stale_subject, expected, actual}` before mutation),
  `operation: :local` (receipted, authority `:none`), the
  `AshEx4pm.ReceiptStore` behaviour with an ETS implementation, and
  `AshEx4pm.Errors.Refused`. Result metadata `:ash_ex4pm_receipt` carries
  subject/authority/consequence/replay/standing. Merged via `735ab7c`.
- **Strict economic ISA adapter** (69a3feb, 0bec77e): `AshEx4pm.EconomicISA`
  adapter for the canonical economic ISA, with a test qualifying its strict
  boundary (`test/ash_ex4pm/economic_isa_test.exs`). Integrated via PR #1
  (64a2150).
- **sa2a-diataxis repository manifest** (f0a5567): `.sa2a/manifest.json`.

### Fixed

- **Notifier emits relationships loaded on `notification.data`** (8ea0c32):
  the set of emitted relationships is the union of changeset-managed
  relationship names and every resource relationship that is loaded (explicit
  load or `load/2`); objects and event relationships are deduplicated.
  Covered by an ex4pm validator round-trip test and an explicit-load test.
- **Merged attribute-history tests opt in to
  `track_attribute_changes?: true`** (146f423), matching mainline's opt-in
  semantics for changed-attribute capture.
- **`object_type` attribute types validated at compile time; dead
  `compiled.context` removed; `track_attribute_changes?` exercised**
  (6c387f8). `AshEx4pm.ObjectType` moduledoc corrected to state what
  `Transformers.Persist` actually checks.

### Changed

- **`ex4pm` exact-pin moved to the published Hex release 26.10.1.** `mix.exs`
  pins `{:ex4pm, "== 26.10.1"}` (mix.lock checksum
  `269ee75f8226945538ff0627fe5267210a08e951fa6289991e1d3d0bb110782c`), still
  exact-pinned because
  ex4pm's third CalVer component carries contract changes (each release's
  CHANGELOG declares its public contract; see 26.9.9's entry below for the
  original rationale). ex4pm 26.10.1 removes all beam4pm knowledge from ex4pm
  (ex4pm `2fd3a21`): `Ex4pm.Engine.Beam4pm` and its A2A surface are gone
  upstream, and ex4pm's locked dependency set drops its former `a2a` and
  `req` dependencies accordingly.
- **Live ferroplan runtime replaces the generated ferroplan projection.** The
  ggen ferroplan generation unit introduced earlier in this cycle (59eb76f,
  dc5f4dd: `mix ash_ex4pm.ggen.sync`, `priv/ggen/manifest.json`, generated
  `AshEx4pm.Ferroplan` delegate) is retired in this release: the generated
  `lib/ash_ex4pm/ferroplan.ex`, `priv/ggen/templates/ferroplan.ex.eex` and
  `priv/ggen/queries/admitted_ferroplan_activities.rq` are deleted, and the
  ferroplan surface is carried by the live `AshEx4pm.FerroplanRuntime` /
  `AshEx4pm.FerroplanSessions` seams above (`priv/ggen/manifest.json`
  remains). `mix test` asserts the retirement: neither `Ex4pm.Engine.Beam4pm`
  nor `AshEx4pm.Ferroplan` loads.
- **Duplicated validation/lookup logic collapsed** in `persist.ex`,
  `notifier.ex` and `verify.ex` with no behavior change (e96c2f0).
- **Test suite status**: the suite declares 112 `test` blocks across
  `test/**/*.exs` (Elixir 1.20.4-otp-29 / Erlang/OTP 29.1.1, checked
  2026-10-01); wasm-backed tests skip with an explicit named skip when
  `WASM4PM_EX4PM_WASM` is unset.

## [26.9.10] - 2026-09-10

Merge pass over the OCEL 2.0-fidelity swarm's branches (base `9982bfa`),
bringing the suite to 49/49 real tests passing (`test/ash_ex4pm_test.exs`),
still Chicago-style throughout (no mocks).

### Added

- **Composed attribute-emission: declared/typed (default) + opt-in
  automatic public-attribute-change capture.** `AshEx4pm.Notifier.event_attributes/2`
  now takes the full `%Ash.Notifier.Notification{}` (not just post-commit
  `data`) and merges two sources: the existing declared/typed
  `attributes:` schema (unchanged default behavior, unchanged precedence)
  and a new `attribute_change_attributes/2`, gated by a new
  `track_attribute_changes?: boolean` activity DSL field (default
  `false`). When `true` and the firing action is `:update`, every raw,
  PUBLIC (`Ash.Resource.Info.public_attributes/1`) attribute change on
  the notification's changeset that was NOT already explicitly declared
  is captured automatically, string-keyed, into the same emitted event
  `"attributes"` map -- declared/typed values always win on key
  collision. No effect on `:create` (no prior value to diff) or when
  `false` (zero behavior change for existing activities).
- **`manage_relationship`-resolved O2O recovery.** `build_envelope/2`
  now walks every relationship name present as a key in
  `notification.changeset.relationships` (used only to know *which*
  relationships this action's `manage_relationship` calls touched, never
  its raw pre-commit values) and reads the real, resolved, post-commit
  related record(s) directly off `notification.data`, emitting an
  object + `"primary"`-scoped relationship entry per resolved related
  record. `%Ash.NotLoaded{}` values are skipped, never fabricated.
- **Declarative `object_relationship` DSL entity (O2O facts).** A new
  `AshEx4pm.ObjectRelationship` nested entity, declarable inside an
  `activity ... do ... end` block (`object_relationship :customer,
  "placed_by"`), resolved from the notification's own already-loaded
  target record and emitted into the envelope's real
  `"object_relationships"` key (`source_id`/`target_id`/`qualifier`,
  matching `Ex4pm.OCEL.normalize_object_relationships/1`'s accepted
  shape). Compile-time validated against real Ash relationships by
  `AshEx4pm.Verifiers.Verify`. A target not loaded on
  `notification.data` is skipped and logged, never fabricated.

### Rejected (design decision, not merged)

- `fix/notifier-ocel-attributes` -- redundant: dumps raw
  `changeset.attributes` unconditionally with no type coercion and no
  public/private filtering, a real information-disclosure regression
  relative to this release's composed mechanism, which subsumes
  everything it captured more safely.
- `fix/notifier-data-relationships` -- real bug: emits relationships
  based on whether they are *loaded* on `notification.data`, not
  whether this action's `manage_relationship` actually touched them,
  misclassifying ordinary `load:`-driven read-backs as relational
  events. Superseded by this release's changeset-scoped recovery.
- `fix/notifier-relationship-objects` -- stale/regressive branch
  relative to the `299d716` baseline (strips primary-key resolution and
  refusal logging that already exist on main); not a faithful
  alternative design.
- `fix/ocel-attribute-history` -- its correct update-scoped diff logic
  was adapted directly into `attribute_change_attributes/2` above
  rather than merged as a separate parallel code path.

## [26.9.10] - 2026-09-09

Hardening pass: 10 real fixes from an adversarial Ash-maintainer-style review,
bringing the suite to 25/25 real tests passing (`test/ash_ex4pm_test.exs`), still
Chicago-style throughout (no mocks). This pass predates and shipped as part of
the 26.9.10 release (above); its heading was mistakenly left `[Unreleased]`.

### Changed

- **`{:ex4pm, ...}` dependency exact-pinned.** `mix.exs` now pins
  `{:ex4pm, "== 26.9.9"}` instead of `{:ex4pm, "~> 26.9"}`. `ex4pm` has no
  `CHANGELOG.md` or stated versioning policy for its third CalVer component (checked
  `../ex4pm/CHANGELOG.md` directly — it does not exist as of this entry), so a `~>`
  range cannot actually guarantee the compatibility it implies for a real SemVer
  dependency. Exact-pin until `ex4pm` publishes a real versioning policy for that
  component.

### Fixed

- `AshEx4pm.Verifiers.Verify` now also refuses a domain-level `activity` whose
  `resource:` is not a compiled Ash resource, not just a nonexistent `on:` action.
- `AshEx4pm.Notifier.record_id/2` now resolves a resource's real Ash primary key
  instead of assuming `:id` — correctly reads a non-`:id`-named primary key (e.g.
  `:sku`), and falls back to a clearly-synthetic id (`"synthetic_obj_" <> _`, never an
  empty string) when the value is `nil` or the input has no resolvable id at all.
- `AshEx4pm.Changes.BrceGate` validates `actor.capabilities` before use and refuses
  cleanly (`{:error, %Ash.Error.Invalid{}}`) instead of raising when it is a
  malformed non-list (a bare string, map, integer, or tuple).
- The `:activity` Spark DSL entity now carries a real entity-level `describe:` for
  Spark doc generation.
- `AshEx4pm.Activity`'s `@enforce_keys [:name, :on]` and the entity schema's `on:`
  requiredness previously contradicted each other (struct enforced it, schema marked
  it optional) alongside a doc claiming unimplemented implicit inference; the schema
  now genuinely requires `on:`, refused at compile time
  (`Spark.Error.DslError`) instead of silently building `%AshEx4pm.Activity{on: nil}`.
- `AshEx4pm.Transformers.Persist`'s stated ordering-after-Ash's-core-transformers
  rationale (`CachePrimaryKey`, `DefaultPrimaryKey`, `SetRelationshipInformation`,
  `BelongsToAttribute`, `BelongsToSourceAttribute`) is corrected to match what Ash
  actually runs.
- A refused `Ex4pm.Stream.Ingest.ingest_envelope/1` call is now logged
  (`AshEx4pm.Notifier.log_refusal/3`) instead of being silently swallowed.
- `AshEx4pm.Changes.BrceGate`'s `before_action` hook now uses `prepend?: true`, so
  the gate runs before any other `before_action` change on the same resource
  regardless of declaration order in `changes:` — closes a real hazard where a gate
  declared after another change would let that other change's side effect run before
  a refused gate ever halted the action.
- Each receipt's `subject_hash` is now computed per real record data, not just
  per resource+operation — two concurrent creates of the same resource+operation
  with different attribute data previously collapsed to one identical
  `subject_hash`, making them indistinguishable in `Ex4pm.Evidence.Store`.
- The documented single-object-per-envelope scope (a `manage_relationship`-managed
  related record is never included in the emitted OCEL envelope) is now explicit in
  `AshEx4pm.Notifier`'s moduledoc and covered by a dedicated regression test.

### Added

- 18 new tests covering the fixes above (25/25 total, up from 7/7).

## [26.9.9] - 2026-09-09

Initial release.

### Added

- Six-piece Spark DSL extension shape (`AshEx4pm`), mirroring `ash_r2rml`'s
  precedent:
  - **Entity**: `AshEx4pm.Activity` — a real struct (`:name`, `:on`, `:resource`),
    not an anonymous map, for one `activity :name, on: :action` declaration.
  - **Section**: `AshEx4pm.Dsl` — defines the `ex4pm do ... end` section
    (`activity` entities, plus a `provenance_source` option, default
    `:ash_ex4pm`, tagged into every emitted event's metadata).
  - **Transformer**: `AshEx4pm.Transformers.Persist` — normalizes raw DSL
    entities into compiled state; fills in `resource:` automatically for
    resource-level declarations, requires it explicitly at the domain level;
    orders itself after Ash's core transformers
    (`CachePrimaryKey`, `DefaultPrimaryKey`, `SetRelationshipInformation`,
    `BelongsToAttribute`, `BelongsToSourceAttribute`).
  - **Verifier**: `AshEx4pm.Verifiers.Verify` — fails closed
    (`Spark.Error.DslError`) when an `activity`'s `on:` action doesn't exist on
    the target resource, or when two activities share a name on the same
    resource.
  - **Info**: `AshEx4pm.Info` — the standard four-form introspection surface
    (`compiled/1`, `compiled_result/1`, `compiled!/1`, `compiled?/1`,
    `activities/1`).
  - **Notifier**: `AshEx4pm.Notifier` — real `Ash.Notifier` that builds an OCEL
    2.0 envelope for every Ash action matching a compiled `activity` and calls
    `Ex4pm.Stream.Ingest.ingest_envelope/1`. Fire-and-forget: a refused or
    failed ingest never blocks the Ash action, matching `Ash.Notifier`'s
    post-commit semantics.
- `AshEx4pm.Changes.BrceGate` — real `Ash.Resource.Change` gating a
  state-changing action behind `Ex4pm.Evidence.BRCE.execute/4` in a
  `before_action` hook, building the required authority map from the
  changeset's real actor (`:capabilities` field, or a supplied
  `authority_from` function). A BRCE refusal becomes a real
  `Ash.Changeset.add_error/2` before Ash's own mutation runs.
  - **Disclosed scope limitation**: `BRCE.execute/4`'s admission callback is a
    pure placeholder (`fn -> :admitted end`) — it does not wrap the real Ash
    database write, so the BRCE receipt chain reflects admission
    success/failure only, not DB-write success/failure. Named explicitly in
    the module's own moduledoc as an unresolved gap, not claimed as full
    DO-authority coverage.
- 7/7 tests passing (`test/ash_ex4pm_test.exs`), Chicago-style throughout: real
  `Ash.DataLayer.Ets` resources, real `AshEx4pm.Notifier` firing, real calls into
  `ex4pm`'s running `Ex4pm.Evidence.Store` and `Ex4pm.Evidence.BRCE` — no mocks.

### Fixed

- **Spark schema-key vs. struct-field mismatch, `on` vs. `:action`.** The
  `activity` DSL entity's Spark schema key is `on` (matching its real struct
  field `AshEx4pm.Activity.on`), not `:action` — an earlier implementation
  pass used `:action` as the schema key while the struct and verifier code
  read `.on`, which compiled but silently produced entities whose `on` field
  was never populated from the DSL's `on: :create` syntax, so
  `AshEx4pm.Verifiers.Verify`'s action-existence check silently passed
  regardless of what action name was written. Fixed by aligning the Spark
  entity schema (`schema: [name: ..., on: ..., resource: ...]`) with the real
  struct fields, confirmed by the compile-time-typo'd-action test now
  correctly failing closed.

### Non-goals (not yet supported)

- Global notifier injection into an already-declared resource's own
  `notifiers:` list.
- Per-Reactor middleware auto-injection for Reactor-based workflows.

Both are named explicitly in the PRD this release implements
(`~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md` §1.3) as real, unbuilt gaps —
not silently assumed solved.
