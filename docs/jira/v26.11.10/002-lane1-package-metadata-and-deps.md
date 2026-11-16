# ash_ex4pm: Lane 1 — Hex Package Metadata, Files Pruning & CalVer Alignment

- Standing: OPEN
- Created: 2026-11-11 (v26.11.10 release wave)
- Assignee: José Valim (Elixir Creator & Hex Packaging Architect)
- Source: `mix.exs:4-79`, `CHANGELOG.md:1-50`
- Evidence: `mix hex.build` currently packages 82 files including `docs/jira/**` and `docs/sjira/**` (114KB).

## Context & Objectives

In `mix.exs`, the `package/0` configuration currently defines:
```elixir
files: ~w(lib priv mix.exs README.md CHANGELOG.md docs docs/**/*)
```
1. **Redundant Globbing**: In Mix packaging, specifying `docs` recursively includes all directory contents. Adding `docs/**/*` produces redundant glob expansion.
2. **Internal Artifact Leakage**: Including all of `docs` bundles internal issue tickets (`docs/jira/`) and RDF graph checkpoints (`docs/sjira/`) into the published Hex tarball distributed to end-users. HexDocs hosts full documentation generated via `ex_doc` using the `docs/0:extras` list. The Hex tarball should be lean and only package runtime files, licensing, and user-facing guides (`README.md`, `CHANGELOG.md`, `docs/diataxis/`, `docs/INDEX.md`).
3. **CalVer Alignment**: Align `@version` in `mix.exs` with target release `26.11.10`, update `CHANGELOG.md`, and synchronize `test/ash_ex4pm/upgrade_contract_test.exs`.
4. **Dependency Hygiene**: Maintain zero git-based dependencies in production; ensure all dependencies (`ash ~> 3.0`, `spark ~> 2.2`, `ex4pm == 26.10.17`, `igniter ~> 0.5`) resolve strictly via Hex.

## Work to complete

1. Refactor `package/0` in `mix.exs` to prune redundant globs and exclude internal metadata:
   ```elixir
   defp package do
     [
       licenses: ["MIT"],
       links: %{"GitHub" => @source_url},
       maintainers: ["Sean Chatman"],
       files: ~w(lib priv mix.exs README.md CHANGELOG.md docs/INDEX.md docs/diataxis docs/examples)
     ]
   end
   ```
2. Verify that `priv/ggen/vendor/sync.sh` or unnecessary test artifacts inside `priv/` are either excluded or minimal.
3. Advance version to `26.11.10` in `mix.exs` and append release notes for `## [26.11.10] - 2026-11-11` in `CHANGELOG.md`.
4. Update `test/ash_ex4pm/upgrade_contract_test.exs` contract assertion to match `@version "26.11.10"`.
5. Run `mix hex.build` and verify that the package builds cleanly with reduced file count and zero packaging warnings.

## Acceptance

- `mix hex.build` completes with exit code 0.
- `docs/jira/` and `docs/sjira/` are excluded from the output `.tar` file.
- All dependencies in `mix.lock` remain strictly Hex-resolved.
- `mix verify` passes cleanly with format check, zero compiler warnings, and green tests.

## History

- 2026-11-11 | OPEN | survey finding | packaging specification established by José Valim.
