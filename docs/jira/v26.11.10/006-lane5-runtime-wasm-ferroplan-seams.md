# ash_ex4pm: Lane 5 — Runtime WASM & Ferroplan Seams with Fault-Bounded Execution

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Process Mining Integration Engineer
- Source: `lib/ash_ex4pm/wasm_runtime.ex:1-98`, `lib/ash_ex4pm/ferroplan_runtime.ex:1-120`, `lib/ash_ex4pm/ferroplan_sessions.ex:1-110`, `test/ash_ex4pm/wasm_engine_test.exs:1-160`
- Evidence: 4 tests skipped in test suite due to `WASM4PM_EX4PM_WASM` being unset; type spec warnings on `File.read/1` with nil parameters.

## Context & Objectives

`ash_ex4pm` provides integration seams with native foreign execution engines:
1. **`wasm4pm` WASM Runtime Integration**: Runs external WebAssembly modules for high-performance time-series forecasting, statistics calculation (`AshEx4pm.Calculations.Forecast`, `Statistic`), and custom capability projections.
2. **`ferroplan` Planning Engine Integration**: Bridges PDDL domain and problem specifications to automated AI planners (`AshEx4pm.FerroplanRuntime`, `FerroplanSessions`).

### Current Fault Containment Vulnerabilities
- **NIF & Foreign Code Crashes**: In Wasmex/Wasmtime, an out-of-memory error or trap in unverified WASM bytecode can crash the host BEAM node if not isolated behind proper process supervision.
- **Unbounded Scheduler Execution**: Executing heavy WASM forecasting or complex PDDL search directly on BEAM scheduler threads blocks dirty CPU schedulers and degrades application responsiveness.
- **Test Suite Fixture Warnings**: When `WASM4PM_EX4PM_WASM` is unset, `@artifact` resolves to `nil`, triggering compiler type warnings:
  ```
  warning: incompatible types given to File.read/1: File.read(nil)
  warning: incompatible types given to File.read!/1: File.read!(nil)
  ```

## Work to complete

1. Encapsulate WASM calls in `AshEx4pm.WasmRuntime` with crash-resilient process supervision:
   - Execute foreign WASM calls via isolated tasks (`Task.Supervisor.async_nolink`) with configurable execution timeouts (default 5,000ms).
   - Trap exits and return typed errors (`{:error, %AshEx4pm.Errors.WasmTrap{}}` or `{:error, :timeout}`) instead of terminating calling processes.
2. Resolve test compilation type warnings in `test/ash_ex4pm/wasm_engine_test.exs` and `test/ash_ex4pm/capability_projection_test.exs`:
   - Guard `File.read/1` and `File.read!/1` with `if @artifact && File.exists?(@artifact)` checks before invoking file I/O on `nil` attributes.
3. Validate Ferroplan session lifecycle in `AshEx4pm.FerroplanSessions`:
   - Ensure temporary session ETS tables or planner scratch files are deterministically cleaned up on session termination.
4. Document the environment contract (`WASM4PM_EX4PM_WASM`, `FERROPLAN_BIN`) and fallback behaviors in `docs/diataxis/reference/wasm_and_ferroplan_contracts.md`.

## Acceptance

- `mix compile --warnings-as-errors` passes without `File.read(nil)` type warnings.
- Unset `WASM4PM_EX4PM_WASM` environment variable cleanly skips live WASM tests without emitting dialyzer warnings.
- Simulated WASM trap or infinite loop terminates cleanly via timeout without taking down the test runner or host BEAM node.
- All Ferroplan and WasmEngine unit tests pass.

## History

- 2026-11-11 | OPEN | survey finding | WASM fault-boundary and test fixture warning resolution specified by Integration Engineer.
