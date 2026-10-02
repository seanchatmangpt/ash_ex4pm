# Receipt: docs packaging fix — ash_ex4pm 26.10.2

Date: 2026-10-01
Repo: ~/ash_ex4pm (correct repo path; note the task brief's "~/ash_ex4mm" is a typo)
Audit source: ~/ash_pplan/receipts/publish-readiness-audit-2026-10-01.md (MAJORs #2 and #3, ash_ex4pm section)

## Publication state (checked before any change)

`curl -s https://hex.pm/api/packages/ash_ex4pm` (2026-10-01, UTC):
- Published releases: **26.10.1 only** (`has_docs: true`), docs at https://ash-ex4pm.hexdocs.pm/
- **26.10.2 is NOT published** — `latest_version: 26.10.1`.
- Consequence: no re-publish conflict; the docs fix ships in 26.10.2 itself.
  No version bump needed. Docs shipping starts at 26.10.2, not "the next version".

## MAJOR #2 — docs/ missing from package

- Root cause: no `files:` list in `mix.exs` `package/2`; hex defaults exclude `docs/`
  while `docs/0` (docs config) lists `docs/INDEX.md`, `docs/reference/capabilities.md`,
  `docs/explanation/architecture.md`, `docs/PRD-ARD-v26.10.2.md` as extras (all four paths
  verified on disk).
- Fix: `files: ~w(lib priv mix.exs README.md CHANGELOG.md docs docs/**/*)` added to
  `package/2` in `mix.exs`.
  (An initial attempt including `NOTICE` failed `mix hex.build` — NOTICE does not exist
  in this repo; that file belongs to ash_pplan. Removed.)
- Verification (real gate, actual output):
  - `MIX_BUILD_ROOT=_build-docs mix hex.build` → exit 0,
    checksum `3c3338bf36af9adda8aa780afcd93d4bcb56d0c60e5f0275da2a3214a1999333`
    (changed from audit-time ebbe6a29… — expected, the package contents changed).
  - `mix hex.build --unpack` → `docs/` present with 20 files, including all four
    hexdoc extras: INDEX.md, reference/capabilities.md, explanation/architecture.md,
    PRD-ARD-v26.10.2.md. Build artifacts (tar, unpack dir, _build-docs) removed after
    verification.

## MAJOR #3 — missing v26.10.2 tag

- At audit time only v26.9.10 and v26.10.1 existed. Created annotated tag `v26.10.2`
  on the commit containing the docs fix (see below for SHA), message:
  "ash_ex4pm 26.10.2 — realtime broadcaster opt, capability registry, federated Diátaxis".
- Rationale for tagging the fix commit rather than 88e1698 (the "chore(release)" commit):
  26.10.2 is unpublished, so the tagged head should be the exact subject whose tarball
  will be published. Tagging 88e1698 would tag a subject whose package still omits docs/.

## Standing

- hex.publish NOT run (prohibited). Publish of 26.10.2 remains a manual step.
- Tag + main pushed to origin; push confirmed via git output.
