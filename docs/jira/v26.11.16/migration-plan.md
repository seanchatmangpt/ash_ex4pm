# ash_ex4pm migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/ash_ex4pm
- Remote: https://github.com/seanchatmangpt/ash_ex4pm
- Branch: main@14a4271 (tracks origin/main)
- Last commit: 2026-10-08 | commits: 106 | size: 6 MB
- Languages/build: Elixir (mix.exs, mix.lock, .tool-versions), ggen vendor packs under priv/
- Nested repos: none

## Observed state
- Dirty (7): CHANGELOG.md, mix.exs, mix.lock, priv/ggen/vendor/PACKS.lock.json,
  priv/ggen/vendor/provenance.ttl, test/ash_ex4pm/reactor_ocel_middleware_test.exs,
  test/ash_ex4pm/upgrade_contract_test.exs
- Untracked (14): docs/jira/v26.11.10/, docs/jira/v26.11.12/ (jira docs only)
- ahead 0 / behind 0; stash 0; unpushed local branches: 23 (ci/*, feat/*, fix/* — several
  shown with no upstream, e.g. feat/verify-gate-wasm-bridge, fix/activity-* , fix/brce-gate-*)
- Build/dep dirs: none (_build, deps absent)
- Local-only artifact: ash_ex4pm-26.10.17.tar (131 KB) at repo root, tmp/ scripts
- Submodules: none

## What it is
AshEx4pm is the Ash projection layer for ex4pm process evidence, admitted runtime
capabilities, wasm4pm analysis, ferroplan planning, and receipted Ash actions.

## Classification
ACTIVE — census value stands; jira dirs for v26.11.10/v26.11.12 show work within the month.

## Migration risk
HIGH — 23 unpushed local branches is the main exposure; plus 7 modified files (deps bump,
vendor lock, two tests) and two untracked jira dirs. No stash, no secrets observed.

## Recommended action
COMMIT-PUSH
1. `cd /Users/sac/ash_ex4pm && git add -A && git commit -m "wip: v26.11.12 deps/vendor/tests"`
2. `git push origin main`
3. Push every local-only branch: `git push --all origin` (DECISION: prune the 23 fix/feat
   branches that are already merged into main instead of pushing them all).
4. `git for-each-ref --format='%(refname:short) %(upstream)' refs/heads` — verify none lack an
   upstream afterwards.
5. DECISION: keep ash_ex4pm-26.10.17.tar? If yes, move to the archive volume; it is not tracked.
6. On new machine: `git clone https://github.com/seanchatmangpt/ash_ex4pm`.

## First commands on the new machine
- `mix deps.get && mix test` (stated, not run)

## See Also
- ../v26.11.12/
- /Users/sac/docs/jira/v26.11.16/README.md
