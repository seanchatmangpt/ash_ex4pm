# ash_ex4pm: Lane 9 — Hex Package Verification, Tarball Validation & Publishing Gate

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: Hex Marshall (Package Release Engineer & Verification Specialist)
- Source: `mix.exs:44-79`, `mix.lock:1-70`, `~/.hex/hex.config`
- Evidence: `mix hex.user whoami` -> `seanchatman` (code 0); `mix hex.build` generated package with checksum `64451af825aedf9ef40eb814195c10787392c15edc37bca45c4f259620d2a83f` (114KB).

## Context & Objectives

Hex packaging requires strict verification of package contents, file permissions, license declarations, and metadata completeness prior to executing a live release to `hex.pm`.

### Release Gate Checklist
1. **Authentication Verification**:
   - Verify active session for maintainer `seanchatman` via `mix hex.user whoami`.
2. **Package Content Whitelist**:
   - Inspect output from `mix hex.build --unpack` to guarantee no sensitive credentials, `.git/`, `.gemini/`, `_build/`, or temporary editor files leak into the package tarball.
   - Verify that excluding `docs/jira/**` and `docs/sjira/**` reduces tarball bloat while preserving essential documentation files (`README.md`, `CHANGELOG.md`, `docs/INDEX.md`, `docs/diataxis/**`).
3. **Reproducible Tarball Checksum**:
   - Compute SHA-256 digest of the produced `.tar` file and verify byte-identical reproducibility where feasible under pinned timestamps.
4. **Publish Execution vs Archival**:
   - When coordinated by the orchestrator, execute `mix hex.publish --yes` or retain the sealed release tarball `ash_ex4pm-26.11.10.tar` with full publication receipts.

## Work to complete

1. Execute dry-run build and verify tarball contents:
   ```bash
   mix hex.build --output /tmp/ash_ex4pm_release_test.tar
   tar -tvf /tmp/ash_ex4pm_release_test.tar
   ```
2. Verify package metadata:
   - Name: `ash_ex4pm`
   - Version: `26.11.10`
   - Licenses: `["MIT"]`
   - Maintainers: `["Sean Chatman"]`
   - Links: GitHub repository URL
   - Elixir requirement: `~> 1.17`
3. Verify that zero `:git` dependencies exist in `mix.lock`.
4. Validate Hex package build cleanly with exit code 0.
5. Record package checksum, file count, and exact tarball size in the release receipt.

## Acceptance

- `mix hex.build` completes with zero errors, zero warnings, and returns exit code 0.
- All included files are explicitly whitelisted and relevant to runtime consumers.
- Maintainer `seanchatman` confirmed authorized to publish to `ash_ex4pm` on hex.pm.
- Full verification receipt recorded in release documentation.

## History

- 2026-11-11 | OPEN | survey finding | Hex package verification gate and release checklist established by Hex Marshall.
