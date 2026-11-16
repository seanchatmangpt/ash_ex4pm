# ash_ex4pm: Lane 2 — Ash 3.0 DSL, Spark Extension & Domain Code Interface

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Zach Daniel (Ash Framework Creator & Architect)
- Source: `lib/ash_ex4pm/dsl.ex:1-300`, `lib/ash_ex4pm/engine_run_domain.ex:1-8`, `lib/ash_ex4pm/transformers/persist.ex:1-252`, `lib/ash_ex4pm/verifiers/verify.ex:1-166`
- Evidence: Survey 1 audit confirmed `AshEx4pm.EngineRunDomain` uses bare domain declaration without code interfaces; activities allow implicit `object_type` inference from resource name.

## Context & Objectives

As the creator of the Ash Framework, I designed Spark DSL extensions to provide declarative, compile-time validated schemas that prevent runtime schema drift. In `ash_ex4pm`, two high-value architectural improvements are needed:

1. **Code Interface on `AshEx4pm.EngineRunDomain`**:
   - In Ash 3.0, callers should interact with domains through declarative code interfaces rather than constructing changesets manually.
   - Currently, consumers invoke `AshEx4pm.EngineRun` via `Ash.Changeset.for_create(AshEx4pm.EngineRun, :discover, ...)` or raw generic actions.
   - We should define a first-class code interface on `AshEx4pm.EngineRunDomain` exposing:
     - `discover(subject, opts \\ [])`
     - `conform(subject, model, opts \\ [])`
     - `simulate(model, opts \\ [])`
     - `optimize(subject, model, opts \\ [])`
     - `plan(domain_pddl, problem_pddl, opts \\ [])`
     - `by_receipt(receipt_hash, opts \\ [])`
     - `replay(subject, opts \\ [])`
     - `capabilities(opts \\ [])`

2. **Explicit vs Implicit `object_type` Contracts in Spark DSL**:
   - In `lib/ash_ex4pm/dsl.ex`, the `@activity` entity permits omitting `object_type:`. When omitted, `AshEx4pm.Notifier.resource_type_name/1` dynamically derives the type name from the resource module name at runtime.
   - In Ash 3.0, explicit contracts are favored over emergent behavior. An unconfigured `object_type` can cause silent OCEL 2.0 schema fragmentation across renamed modules.
   - `AshEx4pm.Verifiers.Verify` or `AshEx4pm.Transformers.Persist` should enforce or strongly warn when an activity lacks an explicit `object_type` reference that matches a registered `object_type` entity in the domain/resource.

3. **Compiler and Warning Hygiene**:
   - Fix Inspect protocol consolidation warnings during test compilation for `AshEx4pm.Test.WasmProbe` and `AshEx4pm.Test.Series` by moving protocol implementations into `test/support/` loaded before protocol consolidation.

## Work to complete

1. Extend `lib/ash_ex4pm/engine_run_domain.ex` with Ash 3.0 code interface:
   ```elixir
   defmodule AshEx4pm.EngineRunDomain do
     use Ash.Domain, validate_config_inclusion?: false

     resources do
       resource AshEx4pm.EngineRun do
         define :discover, args: [:subject], action: :discover
         define :conform, args: [:subject, :model], action: :conform
         define :simulate, args: [:model], action: :simulate
         define :optimize, args: [:subject, :model], action: :optimize
         define :plan, args: [:subject], action: :plan
         define :by_receipt, args: [:receipt_hash], action: :by_receipt
         define :replay, args: [:subject], action: :replay
         define :capabilities, action: :capabilities
       end
     end
   end
   ```
2. In `lib/ash_ex4pm/verifiers/verify.ex`, add validation ensuring that when an activity specifies `object_type:`, it must correspond to an admitted `object_type` entity. Emit a compile-time advisory if an activity relies on implicit module naming.
3. Add unit tests in `test/ash_ex4pm/engine_run_domain_test.exs` verifying that all defined code interfaces invoke their respective ETS actions with valid parameters.
4. Move protocol implementations in test modules to compile cleanly without protocol consolidation warnings.

## Acceptance

- `AshEx4pm.EngineRunDomain` provides callable code interfaces for all 8 process mining and verification operations.
- `mix compile --warnings-as-errors` passes cleanly with zero warnings.
- Test suite passes 100% including new code interface tests.

## History

- 2026-11-11 | OPEN | survey finding | Ash 3.0 domain interface and DSL validation blueprint established by Zach Daniel.
