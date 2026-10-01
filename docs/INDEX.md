# AshEx4pm documentation

AshEx4pm uses the Diátaxis model. This index separates learning, task execution,
lookup, and architectural explanation instead of making the README carry every
capability detail.

## Tutorials — learning-oriented

- [Inspect your first capability](tutorials/first-capability-inspection.md) —
  discover the projection graph without executing a planner or mutation.
- The README contains the first OCEL resource and the two BRCE change patterns.

## How-to guides — task-oriented

- [Inspect runtime standing](how-to/inspect-runtime-standing.md) — distinguish
  PROJECTED from evidence-bounded runtime standing.
- [wasm4pm how-to documentation](https://github.com/seanchatmangpt/wasm4pm/tree/main/docs/how-to)
  covers the portable runtime's task-oriented guides.

## Reference — information-oriented

- [Capability registry](reference/capabilities.md) — descriptor fields,
  capability IDs, boundaries, authority and standing semantics.
- [ex4pm reference](https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md)
- [wasm4pm reference](https://github.com/seanchatmangpt/wasm4pm/tree/main/docs/reference)
- [ferroplan planning types](https://github.com/seanchatmangpt/ferroplan/blob/main/docs/planning-types.md)
- [ferroplan FOND/HDDL](https://github.com/seanchatmangpt/ferroplan/blob/main/docs/FOND-HTN.md)

## Explanation — understanding-oriented

- [Architecture and authority boundaries](explanation/architecture.md)
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
