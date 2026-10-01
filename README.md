# AshEx4pm

An Ash extension for automatic OCEL 2.0 event emission from Ash resources/domains,
built directly on `ex4pm`'s real, canonical functions — `Ex4pm.Stream.Ingest.ingest_envelope/1`
for real-time notification-based emission, and `Ex4pm.Evidence.BRCE.execute/4` for an
optional pre-commit admission gate.

## Installation

Add `ash_ex4pm` to your `mix.exs` deps:

```elixir
def deps do
  [
    {:ash_ex4pm, "~> 26.10"}
  ]
end
```

`ash_ex4pm` itself pins `ex4pm` exactly (`{:ex4pm, "== 26.10.1"}`, see this repo's own
`mix.exs`), not with a `~>` range: `ex4pm`'s third CalVer component carries contract
changes, and each `ex4pm` release's `CHANGELOG.md` declares that release's public
contract in an explicit "Public contract" subsection, so a `~>` range cannot actually
guarantee the compatibility it implies for a real SemVer package.

`ash_ex4pm` takes `ex4pm` from Hex: `mix.exs` pins the real, published,
checksum-verifiable release `{:ex4pm, "== 26.10.1"}`
([hex.pm/packages/ex4pm/26.10.1](https://hex.pm/packages/ex4pm/26.10.1)); it was a
path dependency only during initial co-development (see this repo's git history).
A path pin remains an alternative when developing against a sibling `ex4pm`
checkout:

```elixir
{:ex4pm, path: "../ex4pm"}
```

## Usage

Declare an `ex4pm do ... end` block inside an `Ash.Resource`, add
`extensions: [AshEx4pm]` to compile the DSL, and add `notifiers: [AshEx4pm.Notifier]`
explicitly so emission actually fires (see "Non-goals" below — this is not automatic).
This example mirrors the real resource this extension's own test suite exercises
(`test/support/test_domain.ex`):

```elixir
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

    update :ship do
      accept([])
      change(set_attribute(:status, :shipped))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:status, :atom, default: :pending, public?: true)
  end
end

defmodule MyApp.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(MyApp.Order)
  end
end
```

Calling `Ash.Changeset.for_create(:create, ...) |> Ash.create()` fires
`AshEx4pm.Notifier`, which finds the matching `activity` declaration (`on: :create`),
builds a real OCEL 2.0 envelope, and calls `Ex4pm.Stream.Ingest.ingest_envelope/1`. An
action with no matching `activity` (like `:ship` above, which has no
`activity ..., on: :ship` declared) emits nothing. A refused or failed ingest never
blocks the Ash action itself — the notifier is fire-and-forget and runs post-commit,
matching `Ash.Notifier`'s own post-commit semantics.

Introspect the compiled DSL state via `AshEx4pm.Info`:

```elixir
AshEx4pm.Info.compiled?(MyApp.Order)
# => true

AshEx4pm.Info.activities(MyApp.Order)
# => [%AshEx4pm.Activity{name: :order_created, on: :create, resource: MyApp.Order}]
```

`activity` entities can also be declared at the domain level (`ex4pm do ... end` inside
`Ash.Domain`), in which case `resource:` must be set explicitly — there's no implicit
resource to infer it from. `AshEx4pm.Verifiers.Verify` fails the compile
(`Spark.Error.DslError`) if an `activity`'s `on:` action doesn't actually exist on the
target resource, or if two activities declare the same name for the same resource.

## The BRCE gate: `AshEx4pm.Changes.BrceGate`

For state-changing actions that need pre-commit authorization rather than
post-commit notification, add `AshEx4pm.Changes.BrceGate` as a `change`:

```elixir
create :create do
  change({AshEx4pm.Changes.BrceGate, operation: :create_order})
end
```

This wires `Ex4pm.Evidence.BRCE.execute/4` — the sole authority `ex4pm` designates for
gating a state-changing callback — ahead of the Ash action's own mutation, via a
`before_action` hook. The authority map BRCE requires (`%{capabilities: [...]}`) is
built from the changeset's real actor: by default, the actor's own `:capabilities`
field is used directly (an actor with no `:capabilities` gets an empty authority map
and is refused); pass `authority_from: fun` (arity 1, changeset -> map) to override. A
BRCE refusal becomes a real Ash changeset error via `Ash.Changeset.add_error/2` — the
action never reaches Ash's own mutation on refusal.

**Disclosed scope limitation** (from the module's own moduledoc): `BRCE.execute/4`'s
`fun` argument here is a pure admission placeholder (`fn -> :admitted end`), not the
real database write — Ash's own action pipeline performs the actual mutation
separately, after this `before_action` hook returns. This means BRCE's outcome receipt
reflects real ADMISSION success/failure, not real DB-write success/failure; a DB error
after admission is not captured in the BRCE receipt chain. Wrapping the real Ash
mutation itself inside `fun` would require calling into Ash's changeset-apply
internals from a `before_action` hook, which is not attempted in this release — named
honestly as a real, unresolved gap rather than claimed as full DO-authority coverage.

## Status

Real, working code: the suite declares `112` tests (counted with
`grep -rc 'test "' test/ --include='*.exs'`; wasm-backed tests skip with an
explicit named skip when `WASM4PM_EX4PM_WASM` is unset), no mocks — real
`Ash.DataLayer.Ets`
resources, real `AshEx4pm.Notifier` firing, real calls into `ex4pm`'s running
`Ex4pm.Evidence.Store` and `Ex4pm.Evidence.BRCE`. Earlier releases in the 26.9.x
line included 10 real hardening
fixes from an adversarial Ash-maintainer-style review, all covered by the real tests
above (not asserted, exercised):

- `AshEx4pm.Verifiers.Verify` refuses (`Spark.Error.DslError`) a domain-level
  `activity`'s `resource:` that is not a compiled Ash resource, in addition to its
  existing action-existence check.
- `AshEx4pm.Notifier.record_id/2` resolves a resource's real Ash primary key (not a
  hardcoded `:id` assumption) — correctly reads a non-`:id`-named primary key (e.g.
  `:sku`), falls back to a clearly-synthetic id (`"synthetic_obj_" <> _`) for a `nil`
  or unresolvable value, and still handles a plain map's `:id` key for hand-built
  generic-action notifications.
- `AshEx4pm.Changes.BrceGate` validates `actor.capabilities` and refuses cleanly
  (`{:error, %Ash.Error.Invalid{}}`, no raise) when it is a malformed non-list
  (a bare string, map, integer, or tuple), instead of crashing on `Enum.member?`.
- The `:activity` Spark DSL entity carries a real entity-level `describe:` for Spark
  doc generation.
- `AshEx4pm.Activity`'s `@enforce_keys [:name, :on]` and its Spark schema's `on:`
  requiredness now agree — `on:` is genuinely required, refused at compile time
  (`Spark.Error.DslError`) rather than silently defaulting to `nil`.
- `AshEx4pm.Transformers.Persist`'s ordering-after-Ash's-core-transformers rationale
  is corrected and documented against the transformers Ash actually runs.
- A refused `Ex4pm.Stream.Ingest.ingest_envelope/1` call is now logged
  (`AshEx4pm.Notifier.log_refusal/3`), not silently swallowed.
- `AshEx4pm.Changes.BrceGate`'s `before_action` hook uses `prepend?: true`, so the
  gate always runs before any other `before_action` change on the same resource
  regardless of declaration order — a refused gate declared *after* another change in
  the `changes:` list still halts before that other change's side effect runs (real
  regression test using a real `Agent`-backed side-effect counter, not an interaction
  assertion).
- Each admitted/outcome receipt's `subject_hash` is now computed per-record (not just
  per resource+operation), so two concurrent creates of the same resource+operation
  with different data get distinguishable subject hashes in `Ex4pm.Evidence.Store`.
- The single-object-per-envelope scope (a `manage_relationship`-managed related
  record is never included in the emitted OCEL envelope, only the action's primary
  object) is documented in the notifier's own moduledoc and covered by a dedicated
  regression test.

Treat the DSL shape as stable for the cases the test suite covers, and everything
else as unverified until exercised.

Explicit non-goals, named in the PRD this implements
(`~/ex4pm/docs/explanation/ash-ex4pm-prd-ard.md`) and not yet supported:

- **Global notifier injection** — `AshEx4pm.Notifier` must be added explicitly to a
  resource's own `notifiers:` list. This extension does not inject itself into an
  already-declared `notifiers:` list.
- **Per-Reactor middleware injection** — no automatic wiring of OCEL emission into
  Reactor-based workflows exists in this release.

## License

MIT
