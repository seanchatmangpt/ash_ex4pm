# Changelog

All notable changes to `ash_ex4pm` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
