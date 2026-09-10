# Changelog

All notable changes to `ash_ex4pm` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

## [Unreleased] - 2026-09-09

Hardening pass: 10 real fixes from an adversarial Ash-maintainer-style review,
bringing the suite to 25/25 real tests passing (`test/ash_ex4pm_test.exs`), still
Chicago-style throughout (no mocks).

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
