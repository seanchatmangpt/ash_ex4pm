# v26.10.1 lane map (same-checkout fan-out, 2026-10-01)

Goal: upgrade ash_ex4pm to published ex4pm 26.10.1, land the engine/capability/wasm wave, release ash_ex4pm v26.10.1 to Hex, retire lane build roots.

Coordinator owns all git transitions, integration, publish. Agents: no git state commands, no publish.

| lane | kind | build root | owns (exclusive write) |
|---|---|---|---|
| 1 | read-only survey | _build-lane1 | — |
| 2 | write | _build-lane2 | lib/ash_ex4pm/wasm_runtime.ex, lib/ash_ex4pm/call_log_bridge.ex, test/ash_ex4pm/wasm_runtime_test.exs, test/ash_ex4pm/call_log_bridge_test.exs |
| 3 | write | _build-lane9 | lib/ash_ex4pm/engine_run.ex, lib/ash_ex4pm/engine_run_domain.ex, lib/ash_ex4pm/changes/run_engine.ex, lib/ash_ex4pm/calculations/**, lib/ash_ex4pm/capability_projection.ex, lib/ash_ex4pm/ferroplan_sessions.ex, lib/ash_ex4pm/ferroplan_runtime.ex, test/ash_ex4pm/engine_run_test.exs, test/ash_ex4pm/capability_projection_test.exs, test/ash_ex4pm/ferroplan_runtime_test.exs |
| 4 | write | _build-lane4 | mix.exs, mix.lock, CHANGELOG.md, README.md, test/ash_ex4pm/upgrade_contract_test.exs |
| 5 | audit + micro-write | _build-lane5 | .gitignore |

Seams pinned in advance: changelog claims must match files present in tree (lane 4 writes, coordinator verifies); cross-lane compile breakage reported as seams, never fixed in another lane's files; staged deletions (lib/ash_ex4pm/ferroplan.ex, priv/ggen/queries/admitted_ferroplan_activities.rq, priv/ggen/templates/ferroplan.ex.eex) belong to lane 3's semantic scope, committed by coordinator with lane 3's commit.

## History

- 2026-10-01T11:05Z | ALIVE | feat/verify-gate-wasm-bridge a02bb6c | 5-lane fan-out (5 default-agents, one message, disjoint ownership): lane1 contract diff ex4pm 26.9.30→26.10.1 = zero BREAKS, Hex artifact byte-identical to ~/ex4pm v26.10.1; lane2 wasm/call_log 10/10 (singleton Evidence.Store fix); lane3 engine/capability/ferroplan 20/20 w/ wasm env (object_type opt + Forbidden error class); lane4 @version 26.10.1 + CHANGELOG/README + upgrade_contract 4/4; lane5 publish audit (creds seanchatman, hex 2.5.1 per-install repair, dry-run ok). Coordinator seams: .ggen_igniter/manifest reconciled empty, FerroplanRuntime contract + wasm_built?/0. Gates: mix verify EXIT 0 (108 passed / 4 skipped / 0 failed) on elixir 1.20.4-otp-29; format stable under 1.18.4-otp-27.
- 2026-10-01T11:14Z | ALIVE | main 9229ff9 = tag v26.10.1 | published https://hex.pm/packages/ash_ex4pm/26.10.1 (sha 26073c3a…); _build-lane1..9 retired (~2.9GB, artifacts-only verified).
- 2026-10-01T11:35Z | PARTIAL_ALIVE | main 077468b | CI: repo-side setup fixed (setup-beam install-hex/install-rebar false, GitHub bootstrap, MIX_REBAR3 export — commits cc1f607→75a0586). CI previously NEVER green (7/7 setup-beam mirror deaths). Now reaches verify step (first time ever), compiles through the dep tree, blocked upstream: OTP 27 httpc rejects cert chain (key_usage_mismatch, keyCertSign/cRLSign) on release-assets.githubusercontent.com during explorer 0.13 precompiled NIF fetch; curl accepts the same chain; 2 runs × 3 attempts identical. BLOCKED_UPSTREAM_TLS, rerun when CDN/OTP interaction clears or matrix-bump OTP. Local verify EXIT 0 remains the binding release gate.
