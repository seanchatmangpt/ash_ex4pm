# v26.11.10 lane map (same-checkout fan-out, 2026-11-11)

Goal: Coordinate the v26.11.10 Hex package release of `ash_ex4pm`, mature OTP concurrency and process isolation, ensure IEEE OCEL 2.0 and BRCE admission invariants, optimize Hex packaging metadata, and document architectural and governance boundaries across 10 expert agent roles.

Coordinator owns all git transitions, integration, and final Hex publish. Agents operate in disjoint, non-overlapping lanes with exclusive write boundaries; no git state commands and no uncoordinated publish.

| lane | role | persona / specialist | build root | owns (exclusive write) |
|---|---|---|---|---|
| 1 | Packaging & CalVer Alignment | José Valim (Elixir & Packaging Architect) | _build-lane1 | `mix.exs`, `CHANGELOG.md` |
| 2 | Ash 3.0 DSL & Spark Extension | Zach Daniel (Ash Framework Creator) | _build-lane2 | `lib/ash_ex4pm/dsl.ex`, `lib/ash_ex4pm/transformers/persist.ex`, `lib/ash_ex4pm/verifiers/verify.ex`, `lib/ash_ex4pm/engine_run_domain.ex` |
| 3 | BRCE Admission & Invariants | Leslie Lamport (Formal Systems Specialist) | _build-lane3 | `lib/ash_ex4pm/changes/brce_gate.ex`, `lib/ash_ex4pm/changes/receipted_action.ex` |
| 4 | OCEL 2.0 & Process Mining | Wil van der Aalst (Process Mining Pioneer) | _build-lane4 | `lib/ash_ex4pm/notifier.ex`, `lib/ash_ex4pm/evidence/process_evidence.ex`, `lib/ash_ex4pm/engine_run.ex` |
| 5 | WASM & Ferroplan Seams | Process Mining Integration Engineer | _build-lane5 | `lib/ash_ex4pm/wasm_runtime.ex`, `lib/ash_ex4pm/ferroplan_runtime.ex`, `lib/ash_ex4pm/ferroplan_sessions.ex` |
| 6 | Concurrency, OTP & ETS Storage | Joe Armstrong (Erlang/OTP Co-Creator) | _build-lane6 | `lib/ash_ex4pm/application.ex`, `lib/ash_ex4pm/receipt_store/ets.ex` |
| 7 | Realtime Telemetry & Reactor | Chris McCord (Phoenix & Telemetry Specialist) | _build-lane7 | `lib/ash_ex4pm/evidence/realtime_bridge.ex`, `lib/ash_ex4pm/reactor/ocel_middleware.ex` |
| 8 | Diátaxis Docs & Ergonomics | Dave Thomas (Pragmatic Programmer) | _build-lane8 | `docs/diataxis/**`, `docs/INDEX.md`, `README.md` |
| 9 | Hex Verification & Publishing | Hex Marshall (Package Release Engineer) | _build-lane9 | Package tarball audit, `mix hex.build`, publication verification |
| 10 | Security, POLP & Falsification | Security & Governance Auditor | _build-lane10 | `lib/ash_ex4pm/capabilities.ex`, `test/ash_ex4pm/evidence_court.exs`, POLP validation |

## Seams Pinned in Advance

1. **Packaging & ExDoc Seam (Lane 1 ↔ Lane 8 ↔ Lane 9)**:
   - Lane 1 prunes redundant globbing (`docs/**/*`) in `mix.exs:package/0` and excludes internal tickets (`docs/jira/**`, `docs/sjira/**`) from the Hex tarball to keep package size under 120KB.
   - Lane 8 maintains all user-facing Diátaxis documentation (`docs/diataxis/**`) referenced in `mix.exs:docs/0:extras`.
   - Lane 9 validates the resulting tarball checksum (`mix hex.build`) and verifies Hex user credentials (`seanchatman`).

2. **Ash DSL & Domain Code Interface (Lane 2 ↔ Lane 4)**:
   - Lane 2 defines the code interface on `AshEx4pm.EngineRunDomain` (e.g., `discover/2`, `conform/3`, `simulate/2`, `plan/2`).
   - Lane 4 ensures `AshEx4pm.EngineRun` ETS actions map seamlessly to upstream `Ex4pm` algorithms without leaking raw changeset internals to domain callers.

3. **BRCE Transactional & Idempotency Seam (Lane 3 ↔ Lane 6)**:
   - Lane 3 enforces formal separation between admission gates (`BrceGate.before_action`) and consequence actuation (`ReceiptedAction.around_action`).
   - Lane 6 provides caller monitoring (`Process.monitor/1`) in `ReceiptStore.Ets` and wraps claim handling in `try ... after` to guarantee uncommitted `:in_flight` claims never leak or deadlock.

4. **Realtime Ring Buffer & Event Stream (Lane 6 ↔ Lane 7)**:
   - Lane 6 eliminates `:persistent_term` in `RealtimeBridge` to eliminate VM-wide global GC latency spikes.
   - Lane 7 implements an `:ordered_set` ETS ring buffer with atomic monotonic sequencing and decouples the broadcaster using asynchronous dispatch.

5. **WASM Runtime & Engine Run Isolation (Lane 4 ↔ Lane 5 ↔ Lane 10)**:
   - Lane 5 encapsulates external WASM calls behind crash-isolated process boundaries with explicit timeout ceilings.
   - Lane 10 verifies POLP authority ceilings and fail-closed validation on all foreign function invocations.

## History

- 2026-11-11T07:22Z | OPEN | wave initialization | 10 expert agent roles mobilized per user request; pre-flight survey initiated across Ash DSL, OTP concurrency, and Hex packaging lanes.
- 2026-11-11T07:45Z | ALIVE | pre-flight survey 14a4271 | Zach Daniel (Survey 1), Joe Armstrong (Survey 2), and José Valim (Survey 3) complete architectural audits. Hex user `seanchatman` verified. Package checksum `64451af825aedf9ef40eb814195c10787392c15edc37bca45c4f259620d2a83f`. Test suite: 128 passed, 4 skipped, 0 failed.
- 2026-11-11T08:18Z | IN_PROGRESS | docs/jira/v26.11.10/ populated | Release epic `001-epic-v26-11-10-hex-release.md` and 10 modular tickets (`002` through `011`) authored following repository conventions.
