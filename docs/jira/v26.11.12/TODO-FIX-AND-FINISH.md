# TODO-FIX-AND-FINISH (ash_ex4pm)

Standing: UNVERIFIED

Source: PROJECT-REVIEWS.md R4; re-read where marked confirmed.

## Fix

- HIGH `lib/ash_ex4pm/changes/receipted_action.ex:116-121` idempotent `{:replay, entry}` returns
  sealed record before any authority check in this branch (confirmed read); store key and
  fingerprint omitting actor/authority/tenant UNVERIFIED. Check: court where actor lacking
  `:do` replaying a key is refused.
- HIGH `mix.exs:75` `files:` includes `docs`; `docs/jira/` is untracked yet shipped by
  `hex.publish` (confirmed). Check: `mix hex.build` file list excludes `docs/jira`.
- MED version drift: `mix.exs:48` pins ex4pm 26.10.17; CHANGELOG claims sync (ex4pm now
  `26.11.10` per review, UNVERIFIED). Check: pin matches ex4pm release.
- MED `test/ash_ex4pm/evidence_court.exs` not `*_test.exs` (confirmed name): never runs.
  Check: renamed, appears in `mix test` output.
- MED stale `== 26.10.1` pin in README and 5 diataxis docs (UNVERIFIED).
- LOW outcome-write failure labelled `:blocked` (`receipted_action.ex:292-313`); `:in_flight`
  claim without TTL (`:122-130`); replay mismatch returned as success (`:222-234`);
  `brce_gate.ex:85-95` no fallback clause; tautological `upgrade_contract_test.exs`,
  `evidence_pack_test.exs`; sleeps in `call_log_bridge_test.exs:31,97` (all UNVERIFIED).

## Finish

- Add actor/authority/tenant to idempotency key + fingerprint, with court.
- TTL for stuck in-flight claims. Check: expiry court.

## Commit hygiene

- Untracked `docs/jira/v26.11.10/` (confirmed). Uncommitted: CHANGELOG.md, mix.exs, mix.lock,
  `priv/ggen/vendor/{PACKS.lock.json,provenance.ttl}`, two tests. Check: `git status` clean.

## Decide

- Prune `docs/jira` from package `files:` vs keep.
- Pin ex4pm to 26.11.10 or hold 26.10.17.

## Reuse

- `lib/ash_ex4pm/capabilities.ex:224-279` projected/alive/authorized split.
- `lib/ash_ex4pm/capability_projection.ex:69` admission-from-evidence projection.
- `lib/ash_ex4pm/dsl.ex:158-299` Spark DSL + verifier + persist transformer template.
- `lib/ash_ex4pm/notifier.ex:~450-465` public-attributes-only floor; `info.ex:10-37` wrapper.

## See Also

`ex4pm/docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md` · `PROJECT-REVIEWS.md`
