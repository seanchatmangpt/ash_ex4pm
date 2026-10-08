# AshEx4pm Diátaxis

AshEx4pm 26.10.3 — the Ash projection layer for ex4pm process evidence,
admitted runtime capabilities, wasm4pm analysis, ferroplan planning, and
receipted Ash actions.

Diátaxis routes by what you need:

| You want to... | Start here |
|---|---|
| Emit OCEL 2.0 events from an Ash resource, first steps | [Tutorial: Emit OCEL events from an Ash resource](tutorials/emit-ocel-events-from-an-ash-resource.md) |
| Make an Ash action receipted (admission + bound consequence + idempotency) | [How-to: Run a receipted Ash action](how-to/run-a-receipted-ash-action.md) |
| Look up a module, function, option, or refusal reason | [Reference: Public API](reference/api.md) |
| Trace how this repo binds to the ex4pm engine, Reactor middleware, and the WASM embedding | [Reference: Process-Mining Binding Layers](reference/bindings.md) |
| Understand the ownership layering, admission vs DO, and the evidence pack | [Explanation: Architecture](explanation/architecture.md) |

## Where each fact lives

Every claim in this docs set is checked against the shipped modules:

- Extension entrypoint and capability registry: `lib/ash_ex4pm.ex`,
  `lib/ash_ex4pm/capabilities.ex`
- DSL entities: `lib/ash_ex4pm/dsl.ex`; introspection: `lib/ash_ex4pm/info.ex`
- OCEL notifier and optional realtime broadcaster: `lib/ash_ex4pm/notifier.ex`
- Process-mining binding layers: `docs/diataxis/reference/bindings.md`
  (ex4pm pin in `mix.exs`, `lib/ash_ex4pm/reactor/ocel_middleware.ex`,
  `lib/ash_ex4pm/evidence/`, vendored pack in `priv/ggen/vendor/`)
- BRCE changes: `lib/ash_ex4pm/changes/brce_gate.ex`,
  `lib/ash_ex4pm/changes/receipted_action.ex`
- Runtime seams: `lib/ash_ex4pm/wasm_runtime.ex`,
  `lib/ash_ex4pm/ferroplan_runtime.ex`,
  `lib/ash_ex4pm/ferroplan_sessions.ex`, `lib/ash_ex4pm/economic_isa.ex`
- Analytical-run resource: `lib/ash_ex4pm/engine_run.ex`
- Evidence pack (vendored + rendered): `lib/ash_ex4pm/evidence/`,
  `priv/ggen/vendor/`
- Receipt idempotency ledger: `lib/ash_ex4pm/receipt_store.ex`,
  `lib/ash_ex4pm/receipt_store/ets.ex`
- Call-log bridge: `lib/ash_ex4pm/call_log_bridge.ex`
- Generation task: `lib/mix/tasks/ash_ex4pm.ggen.sync.ex`

## Canonical upstream documentation

- ex4pm reference:
  <https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md>
- wasm4pm index:
  <https://github.com/seanchatmangpt/wasm4pm/blob/main/docs/INDEX.md>
- ferroplan planning types:
  <https://github.com/seanchatmangpt/ferroplan/blob/main/docs/planning-types.md>

## See Also (external sibling repositories)

- ex4pm `docs/README.md` (`~/ex4pm`) — the core engine AshEx4pm wraps;
  this repo pins `{:ex4pm, "== 26.10.1"}` (see `mix.exs` — the exact pin
  exists because ex4pm's third CalVer component carries contract changes).
- beam4pm `docs/diataxis/` (`~/beam4pm`) — the OCEL engine layered on the
  ex4pm runtime; beam4pm consumes this repo via `{:ash_ex4pm, "~> 26.10"}`.
