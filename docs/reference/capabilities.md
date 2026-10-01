# Capability registry reference

AshEx4pm.Capabilities is the canonical registry for the Ash-facing projection
surface added in v26.10.2.

It is not a replacement semantic registry for wasm4pm, ferroplan or ex4pm.

## Public API

~~~elixir
AshEx4pm.capabilities()
AshEx4pm.capabilities(owner: :ferroplan)
AshEx4pm.capability(:ferroplan_plan)
AshEx4pm.capability_standing(:ferroplan_plan)

AshEx4pm.Capabilities.available?(:ferroplan_plan)
~~~

## Descriptor fields

Each AshEx4pm.Capability contains:

| Field | Meaning |
|---|---|
| id | Stable AshEx4pm projection identifier |
| category | Process evidence, planning, analysis, admission, actuation, etc. |
| owner | Canonical semantic owner |
| projection | Ash-facing module |
| operation / arity | Export that makes the projection concrete |
| boundary | observe, inspect, analyze, construct, admit, or do |
| authority | none, required, or operation-dependent |
| do_authority? | Whether this projection can cross consequential DO |
| standing | Optional inspection-only standing callback |
| docs | Local and canonical upstream documentation |

## Current capability IDs

- ocel_event_emission
- brce_admission
- receipted_action
- wasm_algorithms
- wasm_statistics
- wasm_forecast
- ferroplan_plan
- ferroplan_plan_production
- ferroplan_session_new
- ferroplan_session_think
- ferroplan_session_replan_following
- ferroplan_session_repair
- ferroplan_session_probe
- capability_projection
- economic_isa_registry

## Boundary law

~~~text
KNOWN
  != PROJECTED
  != AVAILABLE
  != ADMITTED
  != ALIVE
  != AUTHORIZED
  != DO
~~~

A registry entry establishes PROJECTED. available?/1 establishes that the
Ash-facing export is present. standing/1 can return runtime evidence where the
projection supports an inspection-only probe.

Only receipted_action declares do_authority? true in this release.

BrceGate is deliberately different: it performs admission before the Ash
action but its callback is the admission placeholder, so brce_admission
declares boundary :admit and do_authority? false.

## Planning law

Every ferroplan capability in this registry is boundary :construct and
do_authority? false. A plan, repair, probe, policy or replan is a candidate,
not authorization.

## Upstream documentation

- ex4pm: https://github.com/seanchatmangpt/ex4pm/blob/main/docs/diataxis/reference.md
- wasm4pm: https://github.com/seanchatmangpt/wasm4pm/blob/main/docs/INDEX.md
- ferroplan: https://github.com/seanchatmangpt/ferroplan/blob/main/docs/planning-types.md
