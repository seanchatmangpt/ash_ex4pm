# ash_ex4pm: v26.11.10 pre-flight release survey receipt

- Date: 2026-11-11 (v26.11.10 release wave)
- GitHub repo: `seanchatmangpt/ash_ex4pm`
- Local path: `/Users/sac/ash_ex4pm`
- Default branch: `main` | Archived: `false`
- Head commit: `14a4271359186dd613fc97babf1a881d96ecbd13` (`docs(diataxis): doc-hdit scaffolded skeletons (coverage remediation)`)
- Working tree state: 7 uncommitted modifications preparing CalVer baseline:
  - `CHANGELOG.md`: Added release notes for `[26.10.17]`.
  - `mix.exs`: `@version` bumped to `"26.10.17"`, dependency `{:ex4pm, "== 26.10.17"}`.
  - `mix.lock`: Upgraded `ex4pm` (26.10.17), `ash` (3.36.1), `spitfire` (0.4.3).
  - `priv/ggen/vendor/PACKS.lock.json`: Synced from `ggen-marketplace` commit `0a299b821ff5095489627997a93657f6c318fda1`.
  - `priv/ggen/vendor/provenance.ttl`: Synced pack entity provenance.
  - `test/ash_ex4pm/reactor_ocel_middleware_test.exs`: Formatted assertions.
  - `test/ash_ex4pm/upgrade_contract_test.exs`: Contract assertions for `"26.10.17"` and lock checksum `53bafd58...`.

## Hex Packaging & Credentials
- Hex authenticated user: `seanchatman` (`mix hex.user whoami` -> exit code 0).
- Package build verification: `mix hex.build` exited with code 0.
  - Package checksum: `64451af825aedf9ef40eb814195c10787392c15edc37bca45c4f259620d2a83f`
  - Tarball file size: 114KB (`ash_ex4pm-26.10.17.tar`)
  - Packaged files: 82 files across `lib/`, `priv/`, `docs/`, `mix.exs`, `README.md`, `CHANGELOG.md`.

## Test Suite Execution (`mix test`)
- ExUnit execution: **128 passed, 4 skipped, 0 failed** in 1.6s (0.9s async, 0.6s sync).
- Skipped tests (4 total):
  - `test/ash_ex4pm/wasm_engine_test.exs:92` (skip tag: `WASM4PM_EX4PM_WASM unset: no real wasm4pm artifact to execute`)
  - `test/ash_ex4pm/capability_projection_test.exs:83` (skip tag: `WASM4PM_EX4PM_WASM unset: no real wasm4pm artifact to execute`)
- Invariant Evidence Court: `elixir test/ash_ex4pm/evidence_court.exs` -> 5/5 PASS (digest stability, tamper evidence, duplicate stability, malformed refusal).

## Compiler Warnings & Architectural Anomalies
1. **Unmatched / Ignored Test File**:
   - `test/ash_ex4pm/evidence_court.exs`: Script lacks `_test.exs` suffix and uses `Mix.install([{:jason, "~> 1.4"}])`. Mix emits a `:test_load_filters` warning.
2. **Protocol Consolidation Warnings**:
   - `AshEx4pm.Test.WasmProbe` and `AshEx4pm.Test.Series` implement `Inspect` after protocol consolidation.
3. **Dialyzer Type Spec Warning**:
   - `File.read(@artifact)` in `wasm_engine_test.exs:151` and `File.read!(@artifact)` in `capability_projection_test.exs:100` emit type warnings when `@artifact` is `nil` due to unset environment variables.
4. **Missing OTP Application Callback**:
   - `mix.exs` lacks `mod: {AshEx4pm.Application, []}`. Background ETS stores (`AshEx4pm.ReceiptStore.Ets`) and miners rely on imperative startup in `test_helper.exs`.
5. **`:persistent_term` Ring Buffer Contention**:
   - `RealtimeBridge.push/1` updates `:persistent_term` on every event, inducing global GC sweeps and uncoordinated read-modify-write races.

## Multi-Agent Survey Synthesis
- **Zach Daniel (Ash Architect)**: Validated Ash 3.0 DSL and Spark transformers. Recommended adding a domain code interface on `AshEx4pm.EngineRunDomain` and compile-time warnings for implicit `object_type` inference.
- **Joe Armstrong (Concurrency & OTP)**: Identified lack of OTP supervision, `:persistent_term` event buffer anti-pattern, and potential idempotency deadlocks when `ReceiptedAction` crashes without calling `release/2`.
- **José Valim (Hex Packaging)**: Validated zero-git-dependency Hex specification. Recommended pruning redundant `docs/**/*` glob in `package()`, excluding internal tickets (`docs/jira/**`, `docs/sjira/**`), and formalizing CalVer alignment.

10 work-item tickets (`002` through `011`) written alongside this survey receipt.
