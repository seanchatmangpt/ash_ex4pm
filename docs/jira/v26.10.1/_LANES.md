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
