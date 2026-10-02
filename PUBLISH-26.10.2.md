# ash_ex4pm 26.10.2 — Publish Checklist (USER-GATED)

**STATUS 2026-10-01: NOT YET PUBLISHED.** hex.pm lists only 26.10.1
(verified via `https://hex.pm/api/packages/ash_ex4pm`). Dry-run `mix hex.build`
re-verified at HEAD 1621d21 (see step 4 for the current checksum).

**REAL PUBLISH IS USER-GATED. Do not run `mix hex.publish` without explicit
operator approval.**

## Prerequisites

- Hex API key with publish rights on the `ash_ex4pm` package:
  `mix hex.user whoami` must succeed on the publishing machine.
- Working TLS to hex.pm from the publishing machine. CI is currently
  BLOCKED_UPSTREAM_TLS per the v26.10.1 session receipt — publish from this
  laptop, not CI.

## Steps

1. Confirm release state on disk:

   ```sh
   grep -n '@version' mix.exs
   # expect: @version "26.10.2"
   head -22 CHANGELOG.md
   # expect: [26.10.2] entry at top
   git log --oneline -1
   # expect: 1621d21 Merge remote-tracking branch 'origin/main'
   #         (or a descendant; 88e1698 is the release commit, now merged)
   git status --short
   # expect: only untracked `_build*` dirs (e.g. `?? _build-a1/`, `?? _build-lane1/`)
   #         plus this checklist — or clean if _build dirs are ignored
   ```

2. Hex credentials:

   ```sh
   mix hex.user whoami
   # expect your hex.pm username
   ```

   If it fails: `mix hex.user auth` (interactive, local user required).

3. Build the package:

   ```sh
   MIX_BUILD_ROOT=_build-a1 mix hex.build
   # expect: Saved to ash_ex4pm-26.10.2.tar
   # expect: Version: 26.10.2, Build tools: mix, License: MIT
   ```

4. Verify the checksum matches the dry run (re-verified 2026-10-01 at
   HEAD 1621d21; the earlier 5fd968f7… value predates the 1621d21 merge
   and is stale):

   ```sh
   shasum -a 256 ash_ex4pm-26.10.2.tar
   # expected: ebbe6a29afce86c48ca378c1da39f8059af08f019661d6dcbdc2bd0fe88a02a6
   # (reproduced identically on two consecutive `mix hex.build` runs)
   ```

5. Verify package contents (the release reason is actually in the tarball):

   ```sh
   mkdir -p pkg-verify && cp ash_ex4pm-26.10.2.tar pkg-verify/ && cd pkg-verify
   tar -xf ash_ex4pm-26.10.2.tar && tar -xzf contents.tar.gz
   grep -n broadcaster_opts lib/ash_ex4pm/notifier.ex
   # expect 2 matches: call site (line ~176, ingest_envelope opts) and
   # defp broadcaster_opts (line ~203)
   cd .. && rm -rf pkg-verify
   ```

6. REAL PUBLISH (USER-GATED — run manually):

   ```sh
   MIX_BUILD_ROOT=_build-a1 mix hex.publish
   ```

   Review the package listing prompt (must include
   `lib/ash_ex4pm/notifier.ex`, `test/` is excluded, `CHANGELOG.md` present),
   then confirm. Expected: clean publish with docs push
   (`mix docs` verified in-session: `doc/index.html`, `doc/llms.txt`,
   `doc/ash_ex4pm.epub`).

7. Verify after publish:

   ```sh
   mix hex.package fetch ash_ex4pm 26.10.2 --unpack
   grep -n broadcaster_opts lib/ash_ex4pm/notifier.ex
   ```

8. Downstream consumption (only after hex.pm confirms the release is live):

   - `ash_pplan` and `beam4pm` switch to `{:ash_ex4pm, "~> 26.10.2"}`.
   - Do not bump downstream before publish confirmation; no 26.11.0 will
     exist, so `~> 26.10.2` is the correct forward pin.
