# Tutorial: Emit OCEL 2.0 events from an Ash resource

Goal: by the end you have an Ash resource whose `create` and `update`
actions emit real OCEL 2.0 events into ex4pm's ingest path, with typed
object-type schemas and optional realtime fan-out. Takes about 15 minutes.

## Before you start

- Elixir ~> 1.17, Ash ~> 3.0, and `{:ash_ex4pm, "~> 26.10"}` in `deps`
  (see `mix.exs` in the ash_ex4pm repo).
- ex4pm is pinned exactly: `{:ex4pm, "== 26.10.1"}` — its CalVer patch
  component is contract-bearing (`mix.exs`, `deps/`).

## 1. Declare the resource

Create a resource that uses `extensions: [AshEx4pm]`:

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshEx4pm]

  ex4pm do
    activity :order_created, on: :create,
      attributes: [status: :atom],
      qualifier: :orderer

    object_type :order,
      attributes: [status: :atom]
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:status])
    end

    update :ship do
      accept([:status])
      change(set_attribute(:status, :shipped))
      # track every public attribute change not already declared:
      # set on the matching activity, e.g.
      #   activity :order_shipped, on: :ship, track_attribute_changes?: true
    end
  end
end
```

OCEL object-type attributes may also use `:decimal`: object attributes
allow one more type than event attributes (event attributes allow
`:string | :integer | :float | :boolean | :atom | :date | :datetime`).

Notes, each verified in `lib/ash_ex4pm/dsl.ex`:

- `activity :name, on: :action` — both keys required; there is no
  implicit per-action inference.
- `attributes:` on an activity declares the event-type attribute schema
  (allowed types: `:string | :integer | :float | :boolean | :atom |
  :date | :datetime`), validated at compile time by
  `AshEx4pm.Transformers.Persist`.
- `object_type :name, attributes: [...]` additionally allows `:decimal`
  (see `AshEx4pm.ObjectType`'s moduledoc in `lib/ash_ex4pm/dsl.ex`).
- `qualifier` defaults to `"primary"`; set a meaningful role like
  `:orderer` when downstream e2o/o2o queries must distinguish the
  relationship.
- `track_attribute_changes?: true` (update actions only) captures every
  public attribute change not already declared in `attributes:`;
  declared keys win on collision.

## 2. Run it

```elixir
{:ok, order} = Ash.create(MyApp.Order, %{status: :pending})
```

`AshEx4pm.Notifier` runs after commit, builds a wire envelope with
string keys `"schema" / "producer" / "sequence" / "objects" / "events"`
and calls `Ex4pm.Stream.Ingest.ingest_envelope/2`
(`lib/ash_ex4pm/notifier.ex`, `notify/1` and `build_envelope/2`). A
refused ingest never blocks the Ash action — the action already
committed — and the refusal is logged, never silently discarded.

## 3. Add object-to-object facts

Nested `object_relationship` entities declare real OCEL 2.0 O2O facts.
The notifier implements `Ash.Notifier.load/2` so the relationship is
loaded before `notify/1` fires:

```elixir
ex4pm do
  activity :order_placed, on: :create do
    object_relationship :customer, "placed_by"
  end
end
```

(`lib/ash_ex4pm/dsl.ex`, `AshEx4pm.Dsl.ObjectRelationshipEntity`;
loading and resolution in `lib/ash_ex4pm/notifier.ex`.)

## 4. Observe the events in realtime (optional)

Set the broadcaster app env before the first event fires:

```elixir
Application.put_env(:ash_ex4pm, :broadcaster, fn payload ->
  IO.inspect(payload.event_count, label: "ingested events")
end)
```

Accepted shapes (`lib/ash_ex4pm/notifier.ex`, moduledoc; CHANGELOG
26.10.2): `nil` (default), a 1-arity fun called with
`%{envelope:, log:, event_count:}` on fresh ingest only, or
`{mod, fun, args}` with the payload appended. The callback runs
synchronously on the caller's process: a crashing broadcaster raises
out of the action as `Ash.Error.Unknown` (stored receipts survive), so
wrap it in `try/rescue` or a `Task` if you need isolation.

## 5. Check your work

- The resource compiles with no DSL errors — a bad attribute type or an
  unresolvable `object_type` is refused at compile time
  (`lib/ash_ex4pm/transformers/persist.ex`).
- Inspect the compiled declarations:
  `AshEx4pm.Info.compiled(MyApp.Order)` and
  `AshEx4pm.Info.activities(MyApp.Order)` (`lib/ash_ex4pm/info.ex`).
- The notifier is persisted into the resource's `:simple_notifiers`, so
  listing it explicitly in `notifiers:` is redundant but harmless
  (`lib/ash_ex4pm/transformers/persist.ex`,
  `lib/ash_ex4pm/notifier.ex` moduledoc).

## Troubleshooting

- **No events at all** — no `activity` entity's `on:` matches the action
  name; `notify/1` matches `&(&1.on == action_name)` and does nothing
  otherwise (`lib/ash_ex4pm/notifier.ex`).
- **Missing relationship facts** — a relationship whose resolved value
  is `%Ash.NotLoaded{}` is skipped, not emitted with a fabricated id.
- **Cross-resource correlation** — one notification is one resource's
  action; `notify/1` cannot correlate sibling resources' independent
  notifications (permanent constraint, documented in the notifier
  moduledoc). Use a resource-level change that builds a manual
  `%Ash.Notifier.Notification{}` for that case.

## Next steps

- Make an action receipted: [How-to: Run a receipted Ash action](../how-to/run-a-receipted-ash-action.md)
- Full function surface: [Reference: Public API](../reference/api.md)
