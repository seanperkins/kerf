# LoftLine: rename, signed GitHub releases, and an in-app update checker

Status: draft for your review (panel-reviewed, see the end). Date: 2026-10-23. Nothing in this document has been implemented.
Brand decisions (final kit in `docs/mockups/loftline-brand/assets/r4/`): Cut Path direction, Rapid mark, "LoftLine" wordmark
(Regular), IBM Plex Sans + Mono, mark and wordmark kept separate.

## Decisions to confirm

| # | Decision | Recommendation |
|---|---|---|
| 1 | **Updater approach.** Reuse rootkit-game's signed `latest.json` feed with an in-house installer, or Sparkle. | rootkit-game's pattern, ported to Swift. See [Alternatives](#alternatives-considered). |
| 2 | **Rename the GitHub repo** `seanperkins/kerf` to `seanperkins/loftline` (and the local folder). | Yes. GitHub redirects the old URLs. The updater feed uses the new name. This also makes the name public, so the rename is gated on a domain and trademark (classes 9 and 42) check, which has not been done. |
| 3 | **Migrate Kerf data once.** Tool library, custom machines, templates, clipart, gadgets and every saved setting live under the old bundle ID and `Application Support/Kerf`. You said `.kerf` files need not open; this is the other data. One saved setting (`kerf.groupByTool`) decides the order of exported G-code, so losing it changes output. | Yes: one-time copy, old data untouched, run before the app loads anything. Keep a `kerf` alias in the gadget API for one release so your own scripts keep running. |
| 4 | **Version numbers.** | `v0.2.0` is the first release and the first to contain the updater. `v0.2.1` exists to prove an update works. |
| 5 | **Where the brand files go.** | Commit the final kit to `docs/brand/` (about 2.8 MB) and `Resources/AppIcon.icns` (1.6 MB). Leave the round 1 to 5 HTML mockups out of git. |

Sample-sign text changes from "KERF" to "LOFTLINE" in Phase 2 below; say so if you want it left alone.

## Goals

1. Rename the app, file types and repo to LoftLine. Phase 1 changes no G-code byte; Phase 2 changes only the sample content (the sign text), on purpose.
2. Build, sign, notarise and publish a release to GitHub from a tag.
3. Let the app find, verify and install newer releases.

Non-goals: Windows or Linux builds, DMG packaging (zip only), Mac App Store, Intel builds (the README says Apple
Silicon), silent auto-install, Sparkle delta updates, opening `.kerf` files.

## What already exists (evidence)

| Fact | Source |
|---|---|
| Tag-triggered release that signs, notarises, staples and uploads to a GitHub Release, with `workflow_dispatch` as a no-publish rehearsal and a `HAS_SIGNING` guard. Shipped v0.4.1 to v0.5.0. | `~/sites/hacking-bullet-heaven/.github/workflows/release.yml` (rootkit-game) |
| Signed `latest.json` feed on the release: per entry `version`, per-tag `url`, `sha256`, and an RSA-4096 `sig` made with `openssl dgst -sha256 -sign key -binary < archive`. The client embeds the public key, refuses unsigned or oversized fields, compares versions numerically, never updates a dev build. | `tools/update_feed.sh`, `scripts/update/update_feed.gd` |
| Install helper: `ditto -x -k` into a staging dir, atomic swap with rollback, optional relaunch. Updates apply "install now or on quit, never mid-session". Detects App Translocation. | `packaging/updater/macos.sh`, `AGENTS.md` (update channel) |
| Signing vault: private repo with a re-wrapped p12 and a read-only deploy key; ASC API key for notarytool. Key id `4XBH56T7RS` and issuer are checked in, only the `.p8` is secret. | `tools/configure_macos_ci.sh`, skill `apple-ci-signing` |
| shellfling has the same shape of workflow but has never run: no releases, and its vault repo does not exist. | `~/sites/shellfling` |
| Sparkle appears only in the cmux fork (upstream's code) and Talkify (someone else's repo). | `cmux-src/Packages/macOS/CmuxUpdater`, `Talkify/Talkify/Updates` |
| Kerf is SwiftPM-only; the `.app` is assembled by `scripts/bundle.sh` (hand-written Info.plist, ad-hoc signed); the Quick Look `.appex` is built with `swiftc` and signed with its own sandbox entitlements. | `scripts/bundle.sh`, `AGENTS.md` toolchain rules |
| The repo is public, has no tags, no releases, no repo secrets. Its only workflow runs `scripts/check-samples.sh` on `macos-15`. | `gh repo view`, `.github/workflows/samples.yml` |
| The expected G-code and fixtures contain no "Kerf" text, so a pure rename must leave every golden byte-identical. | `git grep -i kerf -- samples/expected` is empty |

## Part A: the rename

### Mapping

| Thing | Old | New |
|---|---|---|
| App name, executable, `.app` | `Kerf`, `Kerf.app` | `LoftLine`, `LoftLine.app` |
| CLI | `kerf-cli` | `loftline-cli` |
| SwiftPM package, product | `Kerf` | `LoftLine` |
| Targets | `KerfApp`, `KerfAppTests` | `LoftLineApp`, `LoftLineAppTests` (`CADCore`, `CAMCore`, `PostCore`, `CGeom` unchanged) |
| Types | `KerfDocument`, `KerfProject`, `KerfFile`, `KerfIOError`, `KerfCommands`, `KerfCLI`, `KerfSnapshot`, `KerfAppDelegate`, `KerfThumbnail*` | same names with the `LoftLine` prefix |
| Bundle ID | `com.seanperkins.kerf` | `com.seanperkins.loftline` |
| Thumbnail extension ID | `com.seanperkins.kerf.thumbnail` | `com.seanperkins.loftline.thumbnail` |
| UTType, MIME | `com.seanperkins.kerf.project`, `application/x-kerf+json` | `com.seanperkins.loftline.project`, `application/x-loftline+json` |
| Project file, tool exchange | `.kerf`, `.kerftools` | `.loftline`, `.loftlinetools` |
| Data directory | `~/Library/Application Support/Kerf/` | `~/Library/Application Support/LoftLine/` |
| Defaults keys | `kerf.pref.*`, `kerf.fileThumbnails` | `loftline.pref.*`, `loftline.fileThumbnails` |
| Gadget JS API | `kerf.*`, `__kerfNative`, `kerf-prelude.js` | `loftline.*`, `__loftlineNative`, `loftline-prelude.js` |
| Environment variables | `KERF_*` (render dir, write samples, update golden, SwiftPM flags, no QL extension, build flags) | `LOFTLINE_*` |
| Window IDs, test temp prefixes | `kerf-help`, `kerf-welcome`, `kerf-tests-…` | `loftline-…` |
| Repo | `seanperkins/kerf` | `seanperkins/loftline` |

Files the rename does not touch (history stays true): past entries in `docs/DECISIONS.md`, `docs/REVIEW-2026-10-20.md`,
`docs/specs/2026-10-19-kerf-design.md`. New decisions are appended to `DECISIONS.md` as usual.

The old name is also a real woodworking word (kerf is the width of a cut). The code search found no use in that sense, but the rename script
lists every prose hit for a human to read before anything is replaced in docs.

### Phase 1: mechanical rename (its own branch, worktree at `.worktrees/loftline-rename`)

One commit per area: SwiftPM manifest and targets; type and file renames; UTI, extension and Info.plist strings; scripts, env vars and CI;
docs and README text, including `AGENTS.md` (its build and test commands name `kerf-cli`, `.kerf` and `KERF_*`) and path literals such as `/nonexistent-kerf-folder` in
`harness/scenarios/export-unwritable.json`. A scripted word-aware replace (`Kerf`/`kerf`/`KERF`) followed by a review of every file it touched.

The sample projects are renamed `samples/*.kerf` to `samples/*.loftline` in this phase (names only; contents wait for Phase 2). Everything that names
them changes with them: the `cp samples/*.kerf …` line in `scripts/bundle.sh`, the glob and `--product` in `scripts/check-samples.sh` (now `loftline-cli`),
the file names `SampleFilesTests` writes (`LOFTLINE_WRITE_SAMPLES`), and the harness projects under `harness/projects/` (`.kerf` to `.loftline`, contents untouched) together with the scenario files that name them by path (for example `harness/scenarios/reel-readme.json`). Golden files are keyed by the sample's base name
(`samples/expected/<post>/sign.nc`), so they do not move.

Acceptance: `scripts/build.sh` and `scripts/test.sh` green (judge by the `Test run with N tests ... passed` line, not the exit code), and
`scripts/check-samples.sh` passes **without `--update`**. Any golden diff means the rename changed behaviour and is a bug. A case-insensitive
search for `kerf` finds only these exceptions, each listed in the commit message:
the history files above; the one-time migration code and its tests; the gadget `kerf` alias; and the sign **artwork** that Phase 2 owns, wherever it is stored:
`"name": "KERF"` inside `samples/sign.loftline`, the `KERF-…` path id in `samples/sign.svg`, `solid kerf_relief` in `samples/relief.stl`, the "KERF" artwork in
`Tests/Fixtures/e2e/sign.svg`, the shape names inside the five `harness/projects/*.loftline`, the scenario selectors that pick that shape by name
(`harness/scenarios/main.json`, `reel-readme.json`; they stay `KERF` until the artwork changes), and the tests that quote any of these.

### Phase 2: content (a separate commit)

- The sign artwork lives in **four** places, each with its own generator or copy, and the social preview is a fifth, separate item:
  1. `SampleFilesTests` writes `samples/` (the sign project, sign SVG, relief STL). Change its text constant ("KERF" to "LOFTLINE", `TextOutliner` in `signSVG()`)
     and the solid name (`kerf_relief` to `loftline_relief`), then regenerate with `LOFTLINE_WRITE_SAMPLES=1 scripts/test.sh --filter SampleFiles`. That one run rewrites the sign project, the sign SVG, the relief STL **and the G-code reference
     `samples/sign.tap`**, so the `.tap` diff is reviewed like any other golden, not skipped.
  2. `EndToEndSignTests.makeSignSVG()` builds the **separate** `Tests/Fixtures/e2e/sign.svg` with its own "KERF" string, and `LOFTLINE_UPDATE_GOLDEN=1` writes that
     SVG **and** its G-code goldens in one run. Change the string, run it once, and review the SVG diff first and the golden diff second; nothing is committed until
     both are reviewed. `EndToEndSignTests` is not `.serialized` and `signSVG()` writes the fixture on every call under that flag, so concurrent tests can write the
     same file: mark the suite `.serialized` (or generate the fixture once before the tests run) before regenerating. `SampleFilesTests` does not touch this file.
  3. `harness/projects/*.loftline` (renamed from `.kerf` in Phase 1: `reel-sign`, `reel-loose`, `sign-loose`, `sign-overcut`, `sign-pause`) store their own copies of the
     old letter outlines, so changing a label does not change the rendered sign. They are rebuilt from the new sign (how is a plan-time detail), and each reel that
     uses one is re-recorded.
  4. The README stills and clips come from the harness: `scripts/ui.sh` for stills and `scripts/reel.sh <scenario>` for the clips (see `docs/UI-HARNESS.md`).
     Re-record them after 1 to 3 are done; the scenario selectors that pick the sign's text shape by name change in this phase, with the artwork.
  5. `docs/images/social-preview.png` is **not** harness output: it is a composed 1280x640 image (card, wordmark, tagline, 3D render of the sign) and nothing in the repo
     produces it. Recreate it from the brand kit plus a fresh 3D preview render of the new sign, and write the recipe into `docs/brand/README.md` so the next
     one is reproducible.
  Review the diffs of 1 and 3 before regenerating any golden; for 2, review the SVG first, then its goldens, as above.
- Only then regenerate goldens (`scripts/check-samples.sh --update`, `LOFTLINE_UPDATE_GOLDEN=1 scripts/test.sh`) and review that diff: the sign programs change
  because the letters change; nothing else should.
- `docs/PARITY.md` and the "about 13 minutes of machine time" claim updated to the new sample.

### Migrating Kerf data (decision 3)

`LegacyKerfMigration` copies the old data into the new locations once, and never modifies the old data.

**When it runs.** In `Sources/LoftLineApp/main.swift`, **after** the CLI check and **before** `LoftLineApp.main()`. After the CLI check, so headless commands
(including the ones `check-samples.sh` runs) never copy user data or raise an alert; a user's custom machines reach the CLI after the app has been opened once.
Not in `applicationDidFinishLaunching`: `ToolLibraryModel.shared` loads `tools.json` while the `App` struct is being built
(`@StateObject private var toolLibrary = ToolLibraryModel.shared`), so a later migration would leave a seeded in-memory library that the next edit
saves over the migrated file. `LOFTLINE_NO_MIGRATION=1` skips it for tests and CI.

**What it copies.**

- Files: `Application Support/Kerf/` (tools, clipart, gadgets, templates, machines) to `LoftLine/`, skipping `Recovery/`; template and tool-exchange
  extensions are renamed. File by file; an existing destination file is **never overwritten** (data made after installing LoftLine wins). Each file is copied to a
  temporary name beside its destination and renamed into place only after the copy succeeds, so an interrupted copy can never leave a partial file that a retry would
  mistake for a finished one. A test injects a failure mid-copy and checks that Retry repairs it.
- Defaults: **every** key in the old `com.seanperkins.kerf` domain whose name starts with `kerf.` is copied to the same name with `loftline.`, and
  `NSWindow Frame Kerf.*` window-frame keys become `NSWindow Frame LoftLine.*`. It is a prefix rule, not a list, because the list is long and drifts:
  today it is `kerf.pref.*`, `kerf.time.*`, `kerf.preview.*`, `kerf.previewScope`, `kerf.groupByTool`, `kerf.fileThumbnails`, `kerf.clipartFolders`,
  `kerf.inspector.expanded.*` and `kerf.document`.
- **`kerf.groupByTool` matters for safety.** `GCodeExporter` uses it to group the exported program by tool (default `false`). A migration that missed it
  would silently change the order of a user's G-code. It has its own test.

**Failure rules.** The completion flag `loftline.migratedFromKerf` is written **last**, only after every copy and key transfer succeeded. A failure is not
retried silently: LoftLine could otherwise run, save a seeded `tools.json` over the missing one, and a later retry would skip that file and mark the migration
done with the real data stranded. Instead the launch shows an alert with the reason and two choices: *Retry* (re-runs the migration, then reloads the tool
library) or *Continue without importing* (writes the flag as `skipped`, an explicit decision, and the old data stays where it is for a manual copy). A scan
test fails if a `"kerf.` string literal remains in `Sources/` outside the migration, so a key added later cannot be forgotten.

The gadget prelude defines `var kerf = loftline;` for one release. Tests run against a temp directory and a temp defaults domain; the migration is removed after a
release or two.

## Part B: signed GitHub releases

### Version and channel

`scripts/bundle.sh` takes `LOFTLINE_VERSION` (numeric `X.Y.Z`, no `v`) and `LOFTLINE_CHANNEL` (`release`, `rehearsal` or `dev`; default `dev`). It writes
the version to `CFBundleShortVersionString` and `CFBundleVersion`, and the channel to a `LoftLineChannel` key. The updater reads the channel and offers
updates only to `release` builds; it never parses version strings to decide whether a build is a dev build.

In the workflow, a tag run sets the version from the tag (the tag must match `^v[0-9]+\.[0-9]+\.[0-9]+$` or the job fails) and the channel to `release`.
A `workflow_dispatch` rehearsal has a `version` input (default `0.0.0`), channel `rehearsal`, and is never published and never in the feed. A dispatch from
`main` therefore cannot stamp the branch name into a bundle or produce a build that thinks it is a release.

### One assembler, parametrised signing

Do not copy the bundle assembly into YAML (shellfling did; it drifts). `scripts/bundle.sh` gains `LOFTLINE_SIGN_IDENTITY` (default `-`, ad-hoc):

1. Copy `packaging/updater/macos.sh` to `Contents/Resources/updater.sh` **before** signing, because the signature and notarisation cover the bundle.
2. Sign **inside-out, without `--deep`**: first the Quick Look `.appex` with `Extensions/QuickLookThumbnail/LoftLineThumbnail.entitlements` plus
   `--options runtime --timestamp`, then the app with `--options runtime --timestamp`. Both reference workflows use `codesign --deep`; that re-signs the
   appex and drops its sandbox entitlements, which breaks the thumbnailer.
3. Verify: `codesign --verify --deep --strict`, and `codesign -d --entitlements -` on the appex must still show the sandbox entitlement.

If the notarised build breaks a gadget (JavaScriptCore JIT) the app gets a `LoftLine.entitlements` with only the entitlement that is proven necessary
(`com.apple.security.cs.allow-jit` is the likely one). Start with none and let the rehearsal decide.

### `.github/workflows/release.yml`

Triggers: tag push `v*`, and `workflow_dispatch` (rehearsal: everything except the publish steps). Runner `macos-15`, matching `samples.yml`. Permissions:
`contents: write` only. Steps, in order:

1. Checkout with `fetch-depth: 0` (tags are needed for the feed's G-code check).
2. **Gate.** `scripts/build.sh`; then `scripts/test.sh` with `set +e`, its output captured to a file (Actions' default shell is `bash -e -o pipefail`, so a
   bare `| tee` would fail on the exit code, which `AGENTS.md` says not to judge by). The step passes only if the output contains a
   `Test run with N tests ... passed` line **and** N is at least `LOFTLINE_MIN_TESTS` (one constant in the workflow, set near the current ~1,200), so a run that
   silently executed far fewer tests fails. A missing line fails the job. The exit code is logged, not used. Then `scripts/check-samples.sh` with no `--update`.
   A release is never built from a red tree.
3. Signing material, guarded by a job-level `HAS_SIGNING` marker (secrets are not usable in step `if:`): read-only deploy key to the vault, runner
   keychain added to the search list, p12 import. Skipped steps fail loudly where a secret is missing, not silently.
4. `LOFTLINE_VERSION=… LOFTLINE_CHANNEL=… LOFTLINE_SIGN_IDENTITY=… scripts/bundle.sh` (values from the rules above).
5. Notarise with the ASC API key (`notarytool submit --wait`), `stapler staple`, `stapler validate`, `spctl --assess --type execute -v`. Key id and issuer are
   checked-in constants, as in rootkit-game; only `ASC_KEY_CONTENT` is a secret.
6. **Smoke on the notarised build** (`scripts/release-smoke.sh`): run the **bundled** executable, `LoftLine.app/Contents/MacOS/LoftLine export <sample> …`, and
   require byte-identical G-code against the golden. `loftline-cli` and `LoftLine` are two SwiftPM products of the same target and `main.swift` handles
   `export` before starting the UI, so the bundled binary has the same code path; the separately built `loftline-cli` that `check-samples.sh` uses is **not**
   the signed binary and proves nothing about hardened runtime. This step proves hardened runtime did not change output.
7. `ditto -c -k --sequesterRsrc --keepParent LoftLine.app LoftLine-vX.Y.Z-macos-arm64.zip` (the only safe zip for a signed bundle).
8. Tag runs only: create the release **as a draft** if missing, `gh release upload --clobber`, notes from `--generate-notes`. A draft is never "latest", so
   no installed app can be offered a release whose feed does not exist yet. If the tag's release already exists and is **published**, the job fails instead of
   uploading (`--clobber` deletes an asset before replacing it, which would leave a public zip and feed briefly inconsistent); a fix ships as a new tag. The workflow
   has `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: false }` so two runs for one tag queue rather than race. Rehearsal runs instead upload the zip as a workflow artifact (7-day retention) so
   the manual checklist below has a build to run after the runner is gone.
9. A second job, `needs:` the first and gated with `if: startsWith(github.ref, 'refs/tags/v')` (`needs` alone only orders jobs; a dispatch rehearsal creates
   no release), builds and uploads the signed feed (Part C), then **verifies** it: `scripts/verify-feed.sh` re-downloads the draft's zip and `latest.json`,
   checks the manifest's `sha256` equals the SHA-256 of the downloaded zip (a valid signature alone does not prove that field), and checks the signature against
   the public key with `openssl`, exactly as the client will. Only if that passes does it publish the draft
   (`gh release edit --draft=false`). A failure leaves the release a draft.
10. `always()` cleanup: vault clone, decoded `.p8`, temp keychain.

The rehearsal cannot check what runs headless can't: 3D preview (runtime Metal shader compile), a gadget run, and the Quick Look thumbnail. These go in
a "release candidate" checklist in `TESTING.md` that you run once on the rehearsal's notarised artifact (downloaded from the workflow run).

### One-time setup (user-run; needs your approval and your credentials)

- Create the private vault repo `seanperkins/loftline-macos-certs`.
- `scripts/configure-release-ci.sh` is an adapted copy of rootkit-game's `tools/configure_macos_ci.sh` with the vault, repo and key id as variables.
  **Do not run the original with `REPO=…loftline`.** It hard-codes `seanperkins/rootkit-macos-certs`, re-wraps the p12 under a new passphrase and pushes it
  there, which would break rootkit-game's `MACOS_CERT_PASSWORD`. A fresh vault also avoids the shared-deploy-key mismatch: the original sets a *new* private
  key as the secret but leaves the vault's old deploy key in place.
- Secrets in `seanperkins/loftline`: `MACOS_CERTS_DEPLOY_KEY`, `MACOS_CERT_PASSWORD`, `ASC_KEY_CONTENT`, `MACOS_IDENTITY`, `UPDATE_SIGN_KEY`.
- Prerequisites I could not verify from the agent sandbox: the `Developer ID Application: Sean Perkins (HH3SJBAS42)` certificate with its private key in
  Keychain Access, and `~/.appstoreconnect/private_keys/AuthKey_4XBH56T7RS.p8`. (A sandboxed `security find-identity` reported 0 identities; I treat that as
  the sandbox, not as the truth.)

## Part C: update checker

### Architecture

- **`UpdateCore`** (new library target, no AppKit, fully unit-tested): `UpdateManifest` (parse and validate), `UpdateVersion` (numeric compare),
  `UpdateSignature` (RSA-4096 verify), `UpdateStateStore` (skipped version, last check).
- **`LoftLineApp/Updates/`**: `UpdateController` (state machine, URLSession), `UpdateSheet` (SwiftUI), the "Check for Updates…" menu item, a
  Preferences toggle, and a banner in the Welcome window.
- **`packaging/updater/macos.sh`**: the install helper, adapted from rootkit-game.
- **`scripts/update-feed.sh`**: adapted from `tools/update_feed.sh`; `genkey` and `<tag>`.

### Feed

`https://github.com/seanperkins/loftline/releases/latest/download/latest.json`. GitHub's `latest` skips pre-releases, so a pre-release channel needs no code.

```json
{ "version": "0.2.1",
  "entries": { "macos-arm64": {
      "version": "0.2.1",
      "url": "https://github.com/seanperkins/loftline/releases/download/v0.2.1/LoftLine-v0.2.1-macos-arm64.zip",
      "sha256": "<64 hex>", "sig": "<base64 RSA-4096>",
      "gcodeChanged": false, "notes": "<first 4000 chars of the release notes>" } } }
```

- The signature is `openssl dgst -sha256 -sign key -binary < archive`. The Swift verifier checks the same bytes: `SecKeyVerifySignature` with
  `.rsaSignatureDigestPKCS1v15SHA256` over a streamed SHA-256 of the file.
- **Acceptance:** a fixture archive signed by the real `scripts/update-feed.sh` (test keypair committed under `Tests/Fixtures/`, labelled test-only)
  verifies; a copy with one flipped byte fails; a signature from another key fails. Production uses a **new** keypair; rootkit-game's key is never reused.
- The client refuses any entry whose `url` does not start with `https://github.com/seanperkins/loftline/releases/download/`, and refuses unsigned, oversized
  or malformed fields rather than clamping them.
- The feed job downloads the release's zip (`gh release download`, as rootkit-game does), signs it, and reads the release notes with
  `gh release view --json body`.
- `gcodeChanged` is true when `samples/expected/` or the golden fixtures differ between the previous tag and this one. **The first release has no previous tag,
  so its value is `false`** (nothing to compare against), stated in the job rather than left to fail.
  `notes` and `gcodeChanged` are not covered by the signature (TLS protects the transport); the archive is.

### Client behaviour

- **When:** automatic check at launch and then daily, only if the preference is on (default on) and the channel is `release`. Dev builds can check
  manually, with a message that they never update, and may override the feed with `LOFTLINE_UPDATE_FEED_URL` (honoured only when the channel is `dev`).
- **Silent on failure** for automatic checks (logged); a manual check reports the error.
- **Result:** an "Update available" entry in the app menu and the Welcome window, plus one sheet per version showing the notes. Choices: *Install and
  Restart*, *Install when I quit* (default), *Skip this version*, *Later*. If `gcodeChanged`, the sheet says the post output changed in this release.
- **Verify before offering install:** download to `~/Library/Caches/LoftLine/Updates/`, check the SHA-256 from the manifest, then the signature. A failure deletes the
  file and reports; nothing is ever executed from an unverified archive.
- **Install, safely:**
  1. The helper is copied out of the bundle to a temp directory (the bundle is about to be replaced).
  2. It is spawned from `applicationWillTerminate`, i.e. only once quit is committed. If the user cancels at a save prompt, nothing is spawned and the
     state stays "will install when you quit".
  3. It receives the app's PID and waits for it to exit. **If the PID is still alive at the timeout it aborts without swapping** (rootkit-game's helper
     swaps regardless, which is wrong for a document app).
  4. It unpacks with `ditto -x -k` into a staging directory beside the target and checks it (`codesign --verify --deep --strict`). Then it renames the current
     app aside to `LoftLine.old-<pid>` and renames the staged app into place; if the second rename fails it renames the old app back. Relaunch if asked.
     **This is two renames, not an atomic swap.** A crash between them leaves no app at the target and `LoftLine.old-<pid>` beside it; the helper's `--recover`
     mode puts it back, and a message tells the user how. The new app deletes any `LoftLine.old-*` next to itself after it launches successfully.
- **Refuses, with a clear message:** a copy running under App Translocation ("move LoftLine to Applications first") or in a location it cannot write.
- **Privacy:** the only request is to github.com, with `User-Agent: LoftLine/<version>`. No identifiers, no analytics. Help gets a short note and the
  toggle turns it off.

### Tests

- `UpdateCoreTests`: manifest (valid, hostile: long fields, bad hex, non-https, wrong host, missing sig), version compare (`0.4.9 < 0.4.10`, suffixes, dev),
  signature (verify, tamper, wrong key), state store.
- Helper tests shell out against a temp directory: successful replace, rollback on a failed unpack, abort when the PID is alive, space in paths, and an
  interruption injected between the two renames (the helper has a test-only fault hook) followed by `--recover`.
- `UpdateController` with a `URLProtocol` stub for the feed and the download.
- `TESTING.md` gets an update-flow script and the release-candidate checklist.

## Alternatives considered

| Option | Why not (or not first) |
|---|---|
| **Sparkle** (SPM, as in the cmux fork and Talkify) | Real strengths: one-click install UI, delta updates, mature. Costs here: a binary framework embedded into a bundle assembled by hand under a CLT-only toolchain; nested inside-out signing of its helpers; a new `THIRD_PARTY.md` entry; an appcast to generate and host. cmux's updater is upstream's code and Talkify is another author's repo, so neither is "ours". Revisit if you want delta updates. |
| **GitHub API notifier only** (compare `tag_name`, open the release page) | Simplest, but the user downloads and replaces the app by hand and there is no signature check. |
| **Ed25519 via CryptoKit instead of RSA-4096** | Slightly simpler Swift, but it would fork the signing tooling away from rootkit-game's `update_feed.sh`. RSA verification through Security.framework is about twenty lines. Revisit only if that proves awkward. |
| **Keep `.kerf` readable** | You said it need not. Files carry a `formatVersion`, not a format name, so this is cheap to add later if you change your mind. |

## Risks and traps

- **Vault overwrite** and **`--deep`** are described above; both are in the reference scripts.
- **Hardened runtime** may break JavaScriptCore JIT (gadgets), runtime Metal shader compilation, or the thumbnailer. Found only by running the notarised build.
- **Public rename.** Renaming the repo and tagging v0.2.0 publishes "LoftLine". Name clearance is still open.
- **Signature byte mismatch** is the classic updater bug; the fixture test above exists for it.
- **A release that changes G-code output** must say so (`gcodeChanged`); the `AGENTS.md` machine-safety rules apply to the post, validator and Z-zero code as before.
- **Old `Kerf.app`** stays installed and keeps registering `.kerf`; remove it by hand after migrating.

## Order of work and acceptance

1. You: confirm decisions 1 to 5; **complete the domain and trademark check**; only then rename the repo; create the vault and secrets; check the Apple prerequisites.
2. Phase 1 rename (acceptance above).
3. Brand: `Resources/AppIcon.icns`, `docs/brand/`.
4. Phase 2 content.
5. The install helper `packaging/updater/macos.sh` and its tests, first, because `bundle.sh` copies it into the bundle and so the first rehearsal needs it to exist.
6. Release pipeline, then a `workflow_dispatch` rehearsal. Green run plus your manual release-candidate checklist.
7. `UpdateCore`, the app layer and the feed job, each with tests.
8. A **second** rehearsal on the final v0.2.0 candidate (it now contains the updater, which the first rehearsal did not) and the release-candidate checklist
   again. Then tag `v0.2.0`; install it to `/Applications` on this Mac.
9. Tag `v0.2.1`. **The updater is not proven until the installed 0.2.0 finds, downloads, verifies, swaps and relaunches as 0.2.1.** Also run one tamper drill: a feed with a wrong digest is refused.

Every outward-facing step (repo rename, vault, deploy key, secrets, tags, releases) is user-run or needs your explicit approval at the time; none happens while this spec is reviewed.

## Review history

Reviewed with the `debate:run` default panel (Executor and Auditor, both Codex) over three revision rounds and two verification passes. Every finding was checked
against the code before it was applied. Findings that changed the design: migrate every `kerf.*` defaults key (one of them, `kerf.groupByTool`, orders exported
G-code) and run the migration before the tool library loads; give rehearsal runs their own channel and version; smoke-test the bundled executable, not a separately built
CLI; draft release, verify feed, then publish; two-rename install with recovery instead of a claimed atomic swap; four separate stores of the sign artwork. The panel's last
verdict was REVISE on small wording and scope details, all of which are now applied. Those last edits were not re-reviewed by the panel.
