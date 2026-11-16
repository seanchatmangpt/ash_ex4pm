# ash_ex4pm: Epic — v26.11.10 Hex Package Release & Architecture Maturation

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Chris McCord (Phoenix & Hex Release Specialist / Coordinator)
- Source: `ORIGINAL_REQUEST.md`, `PROJECT.md`
- Evidence: `mix hex.user whoami` -> `seanchatman`; `mix hex.build` -> checksum `64451af825aedf9ef40eb814195c10787392c15edc37bca45c4f259620d2a83f`; `mix test` -> 128 passed, 4 skipped, 0 failed.

## Overview & Scope

The v26.11.10 release epic coordinates the comprehensive maturation of `ash_ex4pm` as an enterprise-grade Ash 3.0 projection layer over `ex4pm` (and transitively `wasm4pm` and `ferroplan`). It establishes formal quality gates, architectural hardening, and documentation standards across 10 specialized agent roles.

### Core Objectives
1. **Hex Package Integrity**: Prepare and validate the v26.11.10 package tarball, prune redundant file globs, exclude internal task tracking artifacts (`docs/jira/**`, `docs/sjira/**`) from public distributions, and verify package publication readiness under authenticated maintainer `seanchatman`.
2. **Ash 3.0 Ergonomics**: Introduce a first-class code interface on `AshEx4pm.EngineRunDomain` and compile-time contract enforcement for explicit `object_type` declarations in Spark DSL resources.
3. **Formal Invariant Verification**: Verify the mathematical separation of BRCE admission gating (`BrceGate.before_action`) and transactional consequence actuation (`ReceiptedAction.around_action`), ensuring state-space tamper-evidence and crash-resilient idempotency claims.
4. **IEEE OCEL 2.0 Compliance**: Validate process mining discovery, Petri net token replay, and alignment conformance checking across ETS-backed `EngineRun` actions.
5. **OTP Fault Tolerance**: Mature `ash_ex4pm` into a self-contained OTP application with a root supervision tree, eliminate global GC latency caused by `:persistent_term` in `RealtimeBridge`, and add process monitoring (`Process.monitor/1`) to protect `ReceiptStore.Ets` from orphaned in-flight claims.
6. **Telemetry & Real-Time Streaming**: Refactor `RealtimeBridge` to use an atomic `:ordered_set` ETS ring buffer with monotonic sequence counters, and decouple event broadcasters asynchronously to prevent subscriber failures from bubbling into committed Ash transactions.
7. **Developer Experience & Diátaxis**: Audit Diátaxis framework documentation across tutorials, how-to guides, reference documentation, and architectural explanations.
8. **Security & Least Privilege**: Enforce Principle of Least Privilege (POLP) authority ceilings on all external WASM and engine actions, ensuring fail-closed execution semantics.

## Work to complete

1. Coordinate Lane 1 through Lane 10 tasks defined in `_LANES.md`:
   - `002-lane1-package-metadata-and-deps.md` (José Valim)
   - `003-lane2-ash-dsl-and-spark-extension.md` (Zach Daniel)
   - `004-lane3-brce-receipted-action-court.md` (Leslie Lamport)
   - `005-lane4-ocel-process-mining-conformance.md` (Wil van der Aalst)
   - `006-lane5-runtime-wasm-ferroplan-seams.md` (Process Mining Integration Engineer)
   - `007-lane6-concurrency-and-ets-storage.md` (Joe Armstrong)
   - `008-lane7-realtime-telemetry-and-reactor.md` (Chris McCord)
   - `009-lane8-diataxis-documentation-audit.md` (Dave Thomas / Pragmatic Programmer)
   - `010-lane9-hex-package-verification.md` (Hex Marshall)
   - `011-lane10-governance-and-falsification.md` (Security Auditor)
2. Verify package build output via `mix hex.build`.
3. Verify test suite health via `mix test` (128 passed, 0 failed).
4. Verify standalone evidence court via `elixir test/ash_ex4pm/evidence_court.exs`.
5. Complete publication coordination under `seanchatman`.

## Acceptance

- `docs/jira/v26.11.10/` contains complete ticket suite conforming to repository conventions.
- `mix hex.build` builds cleanly with valid metadata, verified files list, and valid package checksum.
- `mix test` executes with 100% passing tests and zero failures.
- All 10 expert agent work orders documented with verifiable acceptance criteria.

## History

- 2026-11-11 | OPEN | epic created | pre-flight survey complete, release coordination active across 10 lanes.
