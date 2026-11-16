# ash_ex4pm: Lane 4 — IEEE OCEL 2.0 Process Mining Conformance & Token Replay

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Wil van der Aalst (Process Mining Pioneer & IEEE OCEL Architect)
- Source: `lib/ash_ex4pm/notifier.ex:1-746`, `lib/ash_ex4pm/evidence/process_evidence.ex:1-186`, `lib/ash_ex4pm/engine_run.ex:1-89`
- Evidence: Notifier emits OCEL 2.0 JSON envelopes with typed event attributes, object relationships, and qualifiers; `EngineRun` executes discovery, conformance, simulation, and replay.

## Context & Objectives

Object-Centric Process Mining (OCPM) moves beyond traditional single-case process mining by acknowledging that real-world business executions involve multiple interacting objects (e.g., Orders, Invoices, Payments, LineItems). `ash_ex4pm` bridges the Ash framework to IEEE OCEL 2.0 standards:

1. **IEEE OCEL 2.0 Standard Conformance**:
   - Every Ash action marked with `@activity` emits an OCEL 2.0 event containing:
     - `id`: Unique event UUID.
     - `type`: Activity name (atom or string).
     - `time`: RFC3339 / ISO8601 UTC timestamp.
     - `attributes`: Typed map of event attributes conforming to `@allowed_attribute_types`.
     - `relationships`: List of typed object references (`%{objectId: id, qualifier: "primary"}`).
   - Object-to-object relationships are loaded during the Ash notifier lifecycle (`Notifier.load/2`) to establish the complete relational graph without N+1 query overhead.

2. **Process Discovery & Conformance Checking Projection**:
   - `AshEx4pm.EngineRun` exposes ETS-backed process mining operations:
     - `:discover`: Directly-Follows Graphs (DFG), Petri nets (Alpha miner, Inductive miner).
     - `:conform`: Token replay and alignment calculation between event logs and Petri net models, returning fitness, precision, and deviation points.
     - `:simulate`: High-level process simulation and queue forecasting.
     - `:replay`: Deterministic event log token replay.

3. **Non-Blocking Post-Commit Ingestion**:
   - `AshEx4pm.Notifier.notify/1` executes post-commit, ensuring that event stream generation cannot revert or stall the underlying business transaction.
   - Event envelopes are validated through `Ex4pm.Stream.Ingest.ingest_envelope/2` to guarantee structural validity before persistence.

## Work to complete

1. Validate OCEL 2.0 JSON event schema against IEEE OCEL 2.0 specifications:
   - Ensure event attributes correctly handle `:decimal`, `:datetime`, `:date`, and nested maps.
   - Verify that synthetic object IDs are only generated when a resource truly lacks a primary key, accompanied by structured warning telemetry.
2. Verify token replay and alignment calculation in `AshEx4pm.EngineRun`:
   - Test conformance checking with known deviating traces (missing mandatory transitions, out-of-order task execution).
   - Verify that fitness scores ($0.0 \le \text{fitness} \le 1.0$) and missing tokens are accurately recorded in `EngineRun.value`.
3. Add conformance benchmark test in `test/ash_ex4pm/engine_run_conformance_test.exs` verifying alignment calculations across 1,000 synthetic multi-object event traces.
4. Document the mathematical mapping from Ash domain events to OCEL 2.0 objects and Petri net transitions in `docs/diataxis/explanation/ocel_and_process_mining.md`.

## Acceptance

- Emitted OCEL 2.0 envelopes pass upstream schema validation (`Ex4pm.OCEL.validate_envelope/1`).
- Token replay accurately calculates trace fitness and detects deviations on synthetic event logs.
- `EngineRun` discovery creates valid Directly-Follows Graphs and Petri net transitions with deterministic SHA-256 receipts.
- All process mining unit tests pass with zero errors.

## History

- 2026-11-11 | OPEN | survey finding | OCEL 2.0 conformance and token replay specification formulated by Wil van der Aalst.
