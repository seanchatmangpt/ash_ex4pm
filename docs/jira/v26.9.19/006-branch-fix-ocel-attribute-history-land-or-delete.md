# ash_ex4pm: land or delete remote branch `fix/ocel-attribute-history`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `fix/ocel-attribute-history` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/ash_ex4pm --head fix/ocel-attribute-history`) or delete (`git push origin --delete fix/ocel-attribute-history`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `fix/ocel-attribute-history`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | fix/ocel-attribute-history | decision pending
