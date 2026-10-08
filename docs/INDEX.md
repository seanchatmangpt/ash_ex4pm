# AshEx4pm documentation

AshEx4pm uses the Diátaxis model. `docs/diataxis/` is the single canonical
docs tree (start at `docs/diataxis/index.md`). This index separates learning,
task execution, lookup, and architectural explanation instead of making the
README carry every capability detail.

## Tutorials — learning-oriented

- [Emit OCEL events from an Ash resource](diataxis/tutorials/emit-ocel-events-from-an-ash-resource.md) —
  first steps with the OCEL 2.0 notifier, from resource to realtime fan-out.
- The README contains the two BRCE change patterns.

## How-to guides — task-oriented

- [Run a receipted Ash action](diataxis/how-to/run-a-receipted-ash-action.md) —
  admission vs receipted DO, idempotency, stale-subject refusal.
- [wasm4pm how-to documentation](https://github.com/seanchatmangpt/wasm4pm/tree/main/docs/how-to)
  covers the portable runtime's task-oriented guides.

## Reference — information-oriented

- [Public API](diataxis/reference/api.md) — capability registry, descriptor
  fields, boundaries, authority, standing semantics, DSL, notifier, changes,
  runtime seams, evidence pack.
- [Capability registry source](../lib/ash_ex4pm/capabilities.ex) — the
  registry itself is code, the reference above documents it.
- [ex4pm reference](https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md)
- [wasm4pm reference](https://github.com/seanchatmangpt/wasm4pm/tree/main/docs/reference)
- [ferroplan planning types](https://github.com/seanchatmangpt/ferroplan/blob/main/docs/planning-types.md)
- [ferroplan FOND/HDDL](https://github.com/seanchatmangpt/ferroplan/blob/main/docs/FOND-HTN.md)

## Explanation — understanding-oriented

- [Architecture](diataxis/explanation/architecture.md) — ownership layering,
  admission vs receipted DO, evidence pack, non-goals.
- [ex4pm explanation](https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/explanation.md)
- [wasm4pm explanation](https://github.com/seanchatmangpt/wasm4pm/tree/main/docs/explanation)

## Product and architecture record

- [v26.10.2 PRD/ARD](PRD-ARD-v26.10.2.md)

## Ownership rule

~~~text
wasm4pm / ferroplan -> own semantics
ex4pm               -> owns admitted runtime and evidence
AshEx4pm             -> owns Ash projection
BRCE / ReceiptedAction -> consequential authority boundary
~~~

Documentation follows the same ownership rule: link to canonical upstream
semantics instead of copying them into this repository.
