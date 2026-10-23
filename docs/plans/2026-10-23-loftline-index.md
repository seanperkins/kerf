# LoftLine plans: order and prerequisites

Spec: `docs/specs/2026-10-23-loftline-rename-and-releases-design.md`. Each plan produces working, tested software on its own and is executed with `ml:executing-plans` in its own worktree under `.worktrees/`.

| # | Plan | Branch / worktree | Needs |
|---|---|---|---|
| 1 | `2026-10-23-loftline-1-rename-and-migration.md`: rename in code, scripts, CI and docs; one-time Kerf data migration | `rename/loftline` / `loftline-rename` | nothing |
| 2 | `2026-10-23-loftline-2-brand-and-sample-content.md`: icon, brand kit, sign text, harness projects, README images | `content/loftline` / `loftline-content` | Plan 1 merged |
| 3 | `2026-10-23-loftline-3-release-pipeline.md`: install helper, `bundle.sh` signing, `release.yml`, rehearsal | `release/pipeline` / `loftline-release` | Plans 1 and 2 merged |
| 4 | `2026-10-23-loftline-4-update-checker.md`: `UpdateCore`, controller and UI, signed feed, v0.2.0 and v0.2.1 proof | `feat/updater` / `loftline-updater` | Plan 3 merged |

**Yours, before Plan 3 Task 6:** finish the domain and trademark (classes 9 and 42) check; rename the repo to `seanperkins/loftline`; confirm the Developer ID certificate and the App Store Connect key exist; run `scripts/configure-release-ci.sh`. **Yours, in Plan 4 Task 8:** set `UPDATE_SIGN_KEY` and approve each tag and workflow run.

Plans 1 and 2 do not touch GitHub settings. Nothing outward-facing happens in any plan except where a task says it needs your approval.
