# LoftLine Plan 3: signed, notarised GitHub releases

> **For agentic workers:** REQUIRED SUB-SKILL: Use ml:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `v*` tag builds, tests, signs, notarises and uploads `LoftLine-vX.Y.Z-macos-arm64.zip` to a draft GitHub Release; a `workflow_dispatch` rehearsal does everything except publish.

**Architecture:** One assembler (`scripts/bundle.sh`) gains version, channel and signing parameters, so CI and local builds share it. Small testable scripts carry the logic that matters (`check-test-run.sh`, `release-smoke.sh`, `check-bundle.sh`); the workflow only orchestrates them. The install helper is built first because the bundle copies it. The feed job and publish step arrive in Plan 4.

**Tech Stack:** zsh, GitHub Actions (`macos-15`), `codesign`, `notarytool`, `stapler`, `ditto`, swift-testing for script tests (shelling out with `Process`).

**Spec:** `docs/specs/2026-10-23-loftline-rename-and-releases-design.md` (Part B). **Depends on Plan 1** (names are post-rename) and Plan 2 (`Resources/AppIcon.icns` exists). Worktree `.worktrees/loftline-release`, branch `release/pipeline`.

## Global Constraints

- SwiftPM only; swift-testing; judge runs by the `Test run with N tests ... passed` line; conventional commits, green at each commit; no attribution lines; never commit on `main`; no time estimates.
- Sign **inside-out, never `--deep`**: Quick Look `.appex` first with `Extensions/QuickLookThumbnail/LoftLineThumbnail.entitlements`, then the app, both `--options runtime --timestamp` when the identity is not ad-hoc.
- Runner `macos-15`; permissions `contents: write` only; zip with `ditto -c -k --sequesterRsrc --keepParent`; asset name `LoftLine-vX.Y.Z-macos-arm64.zip`.
- ASC key id `4XBH56T7RS` and issuer `22e2fb14-d32b-4837-92b0-6280da32716d` are checked-in constants; only `ASC_KEY_CONTENT` is a secret. Secrets in `seanperkins/loftline`: `MACOS_CERTS_DEPLOY_KEY`, `MACOS_CERT_PASSWORD`, `ASC_KEY_CONTENT`, `MACOS_IDENTITY`, `UPDATE_SIGN_KEY` (the last is Plan 4).
- Channel values: `release` (tag runs only), `rehearsal` (dispatch), `dev` (default). Tags must match `^v[0-9]+\.[0-9]+\.[0-9]+$`.
- Never touch `seanperkins/rootkit-macos-certs` or rootkit-game's secrets. Outward-facing steps (vault, deploy key, secrets, workflow runs, tags) happen only in Task 6, with your approval at the time.

## Review Focus

- A dispatch run from `main` must produce a `rehearsal` build with a numeric version, never a build whose version is `main` or whose channel is `release`. Pinned in Task 5.
- A test run that executed far fewer tests, printed `failed`, or printed no result line must fail the gate. Pinned in Task 2.
- A `codesign --deep` regression strips the Quick Look extension's sandbox entitlement. Pinned in Task 3.
- A rerun of a tag whose release is already published must fail, not overwrite assets. Pinned in Task 5.
- The helper must not swap a still-running app, and a crash between its two renames must be recoverable. Pinned in Task 1.

---

### Task 1: The install helper and its tests

**Files:**
- Create: `packaging/updater/macos.sh`, `Tests/LoftLineAppTests/UpdaterHelperTests.swift`

**Interfaces:**
- Produces (CLI, used by Plan 4): `macos.sh --archive <zip> --target <dir holding LoftLine.app> --pid <pid> [--relaunch 1|0] [--state <file>]` and `macos.sh --recover <dir holding LoftLine.app>`. Exit 0 on success; non-zero with a message on stderr otherwise. Env: `LOFTLINE_UPDATER_WAIT_SECONDS` (default 120), `LOFTLINE_UPDATER_SKIP_CODESIGN=1` (tests only), `LOFTLINE_UPDATER_FAULT=between-renames` (tests only: exit 42 after the first rename).

- [ ] **Step 1: Failing tests** (`@Suite .serialized`; build a fake bundle zip with `ditto -c -k --keepParent` of a temp `LoftLine.app` containing `Contents/Info.plist` and a marker file): `replacesTheBundleAndKeepsNoLeftovers` (target holds old app with `marker=old`; after the run `marker=new` and no `LoftLine.old-*` or `.LoftLine-update-*` remain); `abortsWithoutSwappingWhenThePidIsStillAlive` (spawn `/bin/sleep 30`, pass its pid, `LOFTLINE_UPDATER_WAIT_SECONDS=2`: exit non-zero, old app untouched, archive still present); `rollsBackWhenTheArchiveHasNoApp`; `handlesSpacesInEveryPath`; `faultBetweenRenamesLeavesNoAppAndRecoverRestoresTheOldOne` (fault env: exit 42, `LoftLine.app` missing and `LoftLine.old-<pid>` present; `--recover` restores it); `relaunchZeroDoesNotCallOpen` and `relaunchOneOpensTheNewApp` (a stub `open` script first on `PATH` appends its arguments to a file; with `--relaunch 0` the file does not exist, with `--relaunch 1` it holds the new app's path).
- [ ] **Step 2: Run** `scripts/test.sh --filter UpdaterHelper`. Expected: FAIL, script missing.
- [ ] **Step 3: Implement** `macos.sh` (adapted from `~/sites/hacking-bullet-heaven/packaging/updater/macos.sh`; read it first). Differences that matter: wait with `kill -0 "$PID"` until it exits or the wait times out, and **exit without swapping** on timeout; stage with `ditto -x -k` into `<target>/.LoftLine-update-<pid>`; verify the staged app unless skipped (`codesign --verify --deep --strict`); rename the current app to `LoftLine.old-<pid>`, then the staged app into place, rolling back if the second rename fails; honour the fault hook; `--recover` renames the single `LoftLine.old-*` back when `LoftLine.app` is absent; remove the archive and state file only after success; `open` only when `--relaunch 1`. Quote every path.
- [ ] **Step 4: Run** the filter again. Expected: all pass. **Step 5: Commit** `feat(updater): add the install helper with PID wait, rollback and recovery`.

### Task 2: The test-run gate script

**Files:**
- Create: `scripts/check-test-run.sh`, `Tests/LoftLineAppTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Produces: `scripts/check-test-run.sh <logfile> <min-tests>`: `scripts/test.sh` prints one `Test run with N tests in S suites passed|failed …` line per test target (five today: 116, 659, 6, 338 and 329 tests, 1,448 in all). Exit 0 only if there is at least one such line, **every** such line says `passed`, and the **sum** of the N values is `>= min-tests`; otherwise exit 1 with a one-line reason. It never reads an exit code.

- [ ] **Step 1: Failing tests** in `ReleaseScriptsTests` (write temp log files, run the script with `Process`): `acceptsAllPassLinesWhoseSumReachesTheMinimum`; `sumsAcrossTargetLines` (three lines of 100 tests pass a minimum of 300 and fail 301); `rejectsWhenAnyTargetFailed` (four passed lines and one failed line); `rejectsFewerTestsThanTheMinimum`; `rejectsALogWithNoResultLine`.
- [ ] **Step 2: Run** `scripts/test.sh --filter ReleaseScripts`. Expected: FAIL. **Step 3: Implement** the script (zsh, `set -euo pipefail`). **Step 4: Run** again, expected pass. **Step 5: Commit** `feat(release): gate releases on the test result line, not the exit code`.

### Task 3: Version, channel, signing and helper in `bundle.sh`; `check-bundle.sh`

**Files:**
- Modify: `scripts/bundle.sh`
- Create: `scripts/check-bundle.sh`

**Interfaces:**
- Produces: `bundle.sh` env `LOFTLINE_VERSION`, `LOFTLINE_CHANNEL` (`dev` default; `rehearsal`; `release`), `LOFTLINE_SIGN_IDENTITY` (default `-`). Info.plist gains `LoftLineChannel`; `CFBundleShortVersionString` is `LOFTLINE_VERSION` or `0.0.0`; `CFBundleVersion` is `LOFTLINE_VERSION` or `dev-<git describe --always>`. `Contents/Resources/updater.sh` is the Task 1 helper, executable, copied **before** signing. `release` requires `LOFTLINE_VERSION` to match `^[0-9]+\.[0-9]+\.[0-9]+$`; an unknown channel fails.

- [ ] **Step 1: Write `scripts/check-bundle.sh`** (the failing check): runs `bundle.sh` three times and asserts with `plutil -extract` and `codesign`: dev default (`LoftLineChannel` `dev`, version `0.0.0`); `LOFTLINE_VERSION=0.2.0 LOFTLINE_CHANNEL=release` (version `0.2.0`, channel `release`); `LOFTLINE_CHANNEL=release` without a version exits non-zero; `LOFTLINE_CHANNEL=bogus` exits non-zero; then on the last good bundle: `Contents/Resources/updater.sh` exists and is executable; `codesign --verify --deep --strict dist/LoftLine.app` passes; `codesign -d --entitlements - dist/LoftLine.app/Contents/PlugIns/LoftLineThumbnail.appex` still lists `com.apple.security.app-sandbox`; finally `scripts/release-smoke.sh dist/LoftLine.app` passes on the real bundled binary.
- [ ] **Step 2: Run** `scripts/check-bundle.sh`. Expected: FAIL (no channel or version support yet).
- [ ] **Step 3: Implement** in `bundle.sh`: parameter parsing and validation near the top; the new plist keys; copy the helper right after the executable and before any `codesign`; replace the two `codesign -s -` calls with a `sign` step: ad-hoc identity keeps today's commands; any other identity uses `codesign --force --options runtime --timestamp --sign "$LOFTLINE_SIGN_IDENTITY"` for the appex (plus `--entitlements Extensions/QuickLookThumbnail/LoftLineThumbnail.entitlements`) and then for the app (plus `--entitlements Resources/LoftLine.entitlements` only if that file exists). No `--deep` anywhere.
- [ ] **Step 4: Run** `scripts/check-bundle.sh`. Expected: prints `bundle checks passed`. **Step 5: Commit** `feat(release): version, channel and inside-out signing in bundle.sh`.

### Task 4: Smoke script and the signing-setup script

**Files:**
- Create: `scripts/release-smoke.sh`, `scripts/configure-release-ci.sh`
- Modify: `Tests/LoftLineAppTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Produces: `scripts/release-smoke.sh <LoftLine.app>`: runs `<app>/Contents/MacOS/LoftLine export samples/sign.loftline --post generic-grbl-mm --builtin-only --out <tmp> --quiet` and requires byte equality with `${LOFTLINE_SMOKE_EXPECTED_DIR:-samples/expected/generic-grbl-mm}/sign.nc`. `scripts/configure-release-ci.sh <exported.p12>` (user-run): variables `REPO` (default `seanperkins/loftline`), `VAULT` (default `seanperkins/loftline-macos-certs`), `ASC_KEY_ID` (default `4XBH56T7RS`).

- [ ] **Step 1: Failing tests** (the smoke tests use a fake app, a shell script at `<tmp>/LoftLine.app/Contents/MacOS/LoftLine` that copies the golden to its `--out` directory, because a test must not run `swift build` inside `swift test`; the real binary is exercised by `check-bundle.sh`): `smokePassesWhenTheAppWritesTheGoldenBytes`; `smokeFailsWhenAGoldenByteDiffers` (copy the expected dir to a temp folder, flip one byte, point `LOFTLINE_SMOKE_EXPECTED_DIR` at it: exit non-zero); `configureScriptRefusesTheRootkitVault` (`VAULT=seanperkins/rootkit-macos-certs scripts/configure-release-ci.sh /nonexistent.p12` exits non-zero with `refusing` on stderr before any other check); `configureScriptHasNoSyntaxErrors` (`zsh -n`).
- [ ] **Step 2: Run** `scripts/test.sh --filter ReleaseScripts`. Expected: FAIL.
- [ ] **Step 3: Implement** both scripts. `configure-release-ci.sh` is a copy of `~/sites/hacking-bullet-heaven/tools/configure_macos_ci.sh` with these changes: the rootkit-vault guard runs first; the vault repo is created with `gh repo create "$VAULT" --private` if it does not exist; a **new** read-only deploy key is generated and added on every run with the title `loftline GitHub Actions (read-only)` (never "leave existing", which is what makes the original unsafe to reuse); secrets are set only in `$REPO`: `MACOS_CERTS_DEPLOY_KEY`, `MACOS_CERT_PASSWORD`, `ASC_KEY_CONTENT`, `MACOS_IDENTITY`; it never writes to another repo's vault or secrets.
- [ ] **Step 4: Run** the filter again; expected pass. **Step 5: Commit** `feat(release): smoke test on the bundled executable and a guarded signing setup script`.

### Task 5: `release.yml` and its structural check

**Files:**
- Create: `.github/workflows/release.yml`, `scripts/check-release-workflow.sh`
- Modify: `TESTING.md` (release-candidate checklist), `docs/DECISIONS.md`

**Interfaces:**
- Produces: a workflow named `release`; env `LOFTLINE_MIN_TESTS` (the sum across targets, set a little below the current total, which Plan 1 recorded as 1,448).

- [ ] **Step 1: Failing check** `scripts/check-release-workflow.sh` (ruby `YAML.load_file` plus greps) asserting: triggers are `push.tags: [v*]` and `workflow_dispatch` with a `version` input defaulting to `0.0.0`; `runs-on: macos-15`; `permissions: {contents: write}` only; a top-level `concurrency` group containing `github.ref` with `cancel-in-progress: false`; no `--deep` on any `codesign` command that signs (verification commands may use it); `HAS_SIGNING` is a job-level `env`; the gate step references `scripts/check-test-run.sh` and `LOFTLINE_MIN_TESTS`; a step fails a tag that does not match `^v[0-9]+\.[0-9]+\.[0-9]+$`; a step fails when the tag's release exists and is not a draft; release creation uses `--draft`; `actions/upload-artifact` runs only for non-tag runs with `retention-days: 7`; every publish or upload-to-release step is guarded by `startsWith(github.ref, 'refs/tags/v')`; a final `always()` cleanup step removes the vault clone, the decoded `.p8` and the temp keychain.
- [ ] **Step 2: Run** `scripts/check-release-workflow.sh`. Expected: FAIL, file missing.
- [ ] **Step 3: Write `release.yml`.** Steps in order: checkout (`fetch-depth: 0`); resolve version and channel (tag: version from the tag, channel `release`; dispatch: `inputs.version`, channel `rehearsal`; write both to `GITHUB_ENV`); refuse a published release for the tag; gate (`scripts/build.sh`; `set +e` and capture `scripts/test.sh` output to a file; `scripts/check-test-run.sh <file> "$LOFTLINE_MIN_TESTS"`; `scripts/check-samples.sh`); if `HAS_SIGNING != true` on a tag run, fail with the missing-secrets message; the vault deploy key, runner keychain (added to the user search list), p12 import (copy the shape from rootkit-game's `macos` job, `~/sites/hacking-bullet-heaven/.github/workflows/release.yml`); `scripts/bundle.sh` with the three env vars; verify signing (`codesign --verify --deep --strict`, appex sandbox entitlement present, `codesign -dv` shows the `runtime` flag on the app); notarise (`ditto -c -k --sequesterRsrc --keepParent` to a temp zip, `notarytool submit --wait` with the key id and issuer constants), `stapler staple`, `stapler validate`, `spctl --assess --type execute -v`; `scripts/release-smoke.sh dist/LoftLine.app`; zip to `LoftLine-v<version>-macos-arm64.zip`; rehearsal: upload the zip as a workflow artifact; tag: create the release `--draft` if missing and `gh release upload --clobber`; cleanup. Steps that need secrets are skipped (not failed) on a dispatch run without them, so the build-only path works before setup.
- [ ] **Step 4: Run** `scripts/check-release-workflow.sh`. Expected: `workflow checks passed`.
- [ ] **Step 5: Docs.** In `TESTING.md` add "Release candidate checklist" (run on the rehearsal artifact): `spctl --assess` accepts it; the app opens with no Gatekeeper prompt; open the sample sign and the 3D preview renders; run a built-in gadget from the Gadgets menu; `qlmanage -t -s 256 samples/sign.loftline` shows a thumbnail; export G-code for the sample and diff it with the golden. Append a `## Release pipeline (2026-10-23)` entry to `DECISIONS.md` (`one-assembler`, `inside-out-signing`, `rehearsal-channel`, `gate-by-line`, `draft-first`).
- [ ] **Step 6: Commit** `feat(release): add the tag-triggered release workflow and its checks`.

### Task 6: Setup and rehearsal (outward-facing; needs your approval at each step)

**Files:** none.

- [ ] **Step 1: Prerequisites you confirm:** the domain and trademark check is done, the repo is renamed to `seanperkins/loftline`, `Developer ID Application: Sean Perkins (HH3SJBAS42)` is in Keychain Access with its key, and `~/.appstoreconnect/private_keys/AuthKey_4XBH56T7RS.p8` exists.
- [ ] **Step 2: You run** `scripts/configure-release-ci.sh /path/to/exported.p12` and check `gh secret list -R seanperkins/loftline` shows the four secrets.
- [ ] **Step 3: Merge Plan 3 first.** A `workflow_dispatch` workflow must exist on the default branch to be dispatchable, so finish this branch with `ml:finishing-a-development-branch` (PR to `main`, your approval to merge). Tag runs only create a draft release until Plan 4 adds the feed job, so having the workflow on `main` publishes nothing.
- [ ] **Step 4: Rehearse** with approval: `gh workflow run release.yml -R seanperkins/loftline --ref main -f version=0.0.0`; watch to completion. Expected: every step ran (read the log, not just the colour), notarisation `Accepted`, `spctl` accepted, smoke passed, an artifact `LoftLine-0.0.0-macos-arm64` exists, no release was created. A failure is fixed on a new branch and merged, then rerun.
- [ ] **Step 5: Run the release-candidate checklist** on the downloaded artifact and record the results in the PR or the issue tracker. If a gadget or the 3D preview fails under the hardened runtime, add `Resources/LoftLine.entitlements` with only the proven entitlement (likely `com.apple.security.cs.allow-jit`), set it in `bundle.sh` and rerun. Plan 4 builds on this.
