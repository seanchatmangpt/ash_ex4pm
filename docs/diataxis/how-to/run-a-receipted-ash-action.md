# How-to: Run a receipted Ash action

Goal: make a state-changing Ash action produce a real receipt that binds
the actual consequence — not just an admission decision — with optional
idempotent replay and stale-subject refusal.

## Choose the right change first

Two changes, two different guarantees (`lib/ash_ex4pm/changes/brce_gate.ex`,
`lib/ash_ex4pm/changes/receipted_action.ex`):

| | `AshEx4pm.Changes.BrceGate` | `AshEx4pm.Changes.ReceiptedAction` |
|---|---|---|
| Runs | `before_action`, prepended | outermost `around_action`, prepended |
| What the `fun` is | `fn -> :admitted end` (placeholder) | the real Ash mutation |
| Receipt binds | admission only | the real consequence (`artifact_hash` = digest of the resulting record's consequence term) |
| Failed write | not captured | `:blocked` outcome receipt, original Ash error returned |
| Extra | — | idempotency, stale-subject check, authority-free `:local` mode |

Use `BrceGate` when admission alone is the boundary. Use
`ReceiptedAction` when the receipt must bind the real consequence.

## Receipted DO with ReceiptedAction

```elixir
create :create do
  change({AshEx4pm.Changes.ReceiptedAction,
          operation: :create_order,
          idempotency_key: :request_id})
end
```

After a successful run, read the receipt off the record:

```elixir
{:ok, record} = Ash.create(MyApp.Order, %{status: :pending}, ...)

receipt = AshEx4pm.Changes.ReceiptedAction.receipt(record)
receipt.consequence          # sha256 digest (artifact_hash)
receipt.consequence_term     # %{resource, action, primary_key, changed}
receipt.replay               # :fresh | :known_replay
receipt.authority            # authority hash, or :none
receipt.receipt              # %Ex4pm.Evidence.Receipt{phase: :outcome}
```

(`lib/ash_ex4pm/changes/receipted_action.ex`, `receipt_metadata/6` and
`receipt/1`.)

### Options

All verified against `lib/ash_ex4pm/changes/receipted_action.ex`:

- `:operation` (required) — BRCE operation name. `:local` skips
  admission entirely and writes pending/outcome receipts with
  `authority: :none`.
- `:idempotency_key` — an attribute/argument name (read via
  `Ash.Changeset.get_argument_or_attribute/2`), or a
  `fun(changeset) -> key | nil`. With a key present:
  - same key + same fingerprint of a sealed entry returns the sealed
    result with metadata `replay: :known_replay` — the mutation does not
    re-run;
  - same key + different fingerprint is refused
    `{:idempotency_conflict, key}` before mutation;
  - same key still in flight is refused `{:idempotency_in_flight, key}`.
- `:expected_subject` — static expected subject hash; context
  `:expected_subject` wins over the option. A mismatch is refused
  `{:stale_subject, expected, actual}`.
- `:authority_from` — `fun(changeset) -> authority map`. Default derives
  authority from the actor: actor's `:capabilities` field becomes
  `%{capabilities: [...]}`; anything else is `%{}` (shared with
  `BrceGate.authority_for/3`).
- `:store` — module implementing the `AshEx4pm.ReceiptStore` behaviour
  (default `AshEx4pm.ReceiptStore.Ets`).
- `:evidence_store` — the `Ex4pm.Evidence.Store` server (default its
  registered name).

### Start the receipt store

`AshEx4pm.ReceiptStore.Ets` is a GenServer owning a named public ETS
table; the atomic reservation is `:ets.insert_new/2` from the caller's
process. Add it to your supervision tree:

```elixir
children = [
  AshEx4pm.ReceiptStore.Ets
]
```

If the owner is not running, callbacks return
`{:error, :receipt_store_unavailable}` and a keyed action refuses with
`{:receipt_store_unavailable, store}` rather than raising
(`lib/ash_ex4pm/receipt_store/ets.ex`, `lib/ash_ex4pm/errors/refused.ex`).

### Refusals

All refusals surface as `AshEx4pm.Errors.Refused` (class `:forbidden`):

- `{:authority_refused, code}` — BRCE admission refused
- `{:idempotency_conflict, key}`
- `{:idempotency_in_flight, key}`
- `{:stale_subject, expected, actual}`
- `{:receipt_store_unavailable, store}`

(`lib/ash_ex4pm/errors/refused.ex`.)

### Known boundary

The receipt is sealed inside the `around_action` scope. A transactional
commit failure after that hook returns is not yet captured and remains
unverified for transactional data layers (README "BRCE" section;
CHANGELOG 26.10.2). For `update`/`destroy` actions, follow the module
contract and set `require_atomic? false`.

## Admission-only with BrceGate

```elixir
create :create do
  change({AshEx4pm.Changes.BrceGate, operation: :create_order})
end
```

Mechanics (`lib/ash_ex4pm/changes/brce_gate.ex`):

- The gate calls `Ex4pm.Evidence.BRCE.execute/4` with the placeholder
  `fn -> :admitted end`; a `%Ex4pm.Refusal{}` becomes a changeset error
  on `:base` and the Ash mutation never runs.
- The hook is registered with `prepend?: true`, so the gate runs before
  any other `before_action` side effect regardless of declaration order.
- A successful admission stores the receipt in changeset context under
  `:ash_ex4pm_brce_receipt`.
- The subject hash includes resource, operation, the real primary key
  (update/destroy) and the real attribute changes (create), so different
  concurrent changesets do not collapse into one audit subject.

## Next steps

- Wire the events these actions emit into a live consumer:
  [Tutorial: Emit OCEL events](../tutorials/emit-ocel-events-from-an-ash-resource.md)
- Function-level detail: [Reference: Public API](../reference/api.md)
