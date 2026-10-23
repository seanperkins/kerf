# LoftLine Plan 4: signed update feed and in-app update checker

> **For agentic workers:** REQUIRED SUB-SKILL: Use ml:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app finds, downloads, verifies and installs newer signed releases from GitHub, and each release publishes only after its signed `latest.json` feed is verified.

**Architecture:** `UpdateCore` is a pure library target (parse, compare, verify, remember) with no AppKit. `UpdateController` in the app drives a state machine over it with an injectable `URLSession` and an injectable helper launcher. The signing script and the feed job are ports of rootkit-game's `update_feed.sh` and `feed` job with the changes the spec requires (draft, verify, then publish).

**Tech Stack:** Swift (Foundation, Security, CryptoKit), SwiftUI/AppKit, openssl (RSA-4096, PKCS#1 v1.5 over SHA-256), python3 for JSON in the shell script, GitHub Actions.

**Spec:** `docs/specs/2026-10-23-loftline-rename-and-releases-design.md` (Part C and the install section of Part B). **Depends on Plans 1 to 3** (the helper `packaging/updater/macos.sh`, `bundle.sh` channel key, `release.yml`). Worktree `.worktrees/loftline-updater`, branch `feat/updater`.

## Global Constraints

- SwiftPM only; swift-testing; judge runs by the `Test run with N tests ... passed` line; conventional commits, green at each commit; no attribution lines; never commit on `main`; no time estimates.
- Feed URL `https://github.com/seanperkins/loftline/releases/latest/download/latest.json`; platform key `macos-arm64`; every entry `url` must start with `https://github.com/seanperkins/loftline/releases/download/`; `notes` at most 4000 characters; `sha256` exactly 64 lowercase hex characters; unsigned, oversized or malformed fields are refused, never clamped.
- Signature: RSA-4096, PKCS#1 v1.5, made with `openssl dgst -sha256 -sign key -binary < archive`. The client verifies `SecKeyVerifySignature` with `.rsaSignatureDigestPKCS1v15SHA256` over the streamed SHA-256 of the file. The public key is stored as a PKCS#1 `RSA PUBLIC KEY` PEM (what `SecKeyCreateWithData` takes). **A new keypair; rootkit-game's key is never reused.** The private key lives outside the repo (`~/.config/loftline/update_sign.key`, mode 600) and in the secret `UPDATE_SIGN_KEY` (base64).
- Only `release`-channel builds update; `dev` and `rehearsal` never auto-check. `LOFTLINE_UPDATE_FEED_URL` overrides the feed only on the `dev` channel. `LOFTLINE_NO_UPDATE_CHECK=1` disables checks (tests, harness, CI).
- Install never mid-session and never before quit is committed: the helper is spawned only from `applicationWillTerminate`. A translocated or unwritable copy refuses to install. The only network request is to github.com with `User-Agent: LoftLine/<version>`; no identifiers, no analytics.
- Defaults keys: `loftline.pref.autoCheckForUpdates` (Bool, default true), `loftline.update.lastCheck`, `loftline.update.skippedVersion`, `loftline.update.lastPrompted`.

## Review Focus

- A feed whose `url`, `sha256`, `sig` or `notes` is hostile (wrong host, `http`, 65-char hex, 5,000-char notes, missing sig) is refused whole. Pinned in Task 2.
- A one-byte change in the archive, or a signature from another key, is refused, and the downloaded file is deleted. Pinned in Tasks 3 and 4.
- Cancelling quit at a save prompt must not start the helper; the update then waits for the real quit. Pinned in Task 4.
- A dev build, a translocated copy, or a read-only location never installs, and says why. Pinned in Task 4.
- A release must never be visible as "latest" before its feed exists and verifies. Pinned in Task 6.

---

### Task 1: `UpdateCore` target and version comparison

**Files:**
- Modify: `Package.swift` (add `UpdateCore` library target without dependencies, `UpdateCoreTests`; make `LoftLineApp` depend on `UpdateCore`)
- Create: `Sources/UpdateCore/UpdateVersion.swift`, `Tests/UpdateCoreTests/UpdateVersionTests.swift`

**Interfaces:**
- Produces: `public enum UpdateVersion { public static func compare(_ a: String, _ b: String) -> Int; public static func isNewer(_ available: String, than current: String) -> Bool }` (1, 0, -1; dot-separated numeric parts, a leading `v` ignored, a suffix after a digit run ignored, so `0.4.9 < 0.4.10`, `0.4.0-rc1 == 0.4.0`; a part with no digits counts as 0).

- [ ] **Step 1: Failing tests:** `numericNotLexicalOrder` (`compare("0.4.10","0.4.9") == 1`); `suffixAfterDigitsIsIgnored` (`compare("0.4.0-rc1","0.4.0") == 0`); `leadingVIsIgnored`; `missingPartsAreZero` (`compare("1.2","1.2.0") == 0`); `isNewerIsStrict` (equal and older are false).
- [ ] **Step 2: Run** `scripts/test.sh --filter UpdateVersion`. Expected: compile failure (target missing). **Step 3: Implement** the target and the function. **Step 4: Run** again, expected pass. **Step 5: Commit** `feat(update): add UpdateCore with version comparison`.

### Task 2: `UpdateManifest` (parse and validate)

**Files:**
- Create: `Sources/UpdateCore/UpdateManifest.swift`, `Tests/UpdateCoreTests/UpdateManifestTests.swift`

**Interfaces:**
- Produces: `public struct UpdateEntry: Equatable, Sendable { version: String; url: URL; sha256: String; signature: Data; gcodeChanged: Bool; notes: String }` and `public enum UpdateManifest { public static let platformKey = "macos-arm64"; public static let urlPrefix = "https://github.com/seanperkins/loftline/releases/download/"; public static func parse(_ data: Data, platform: String = platformKey) -> UpdateEntry? }` (`nil` on any violation; `gcodeChanged` defaults to false when absent, `notes` to "").

- [ ] **Step 1: Failing tests:** `parsesAValidEntry`; then each of these returns nil: `refusesAWrongHost`, `refusesHttp`, `refusesAUrlPrefixLookalike` (`https://github.com/seanperkins/loftline/releases/download.evil.com/x`), `refusesShortOrUppercaseHex`, `refusesAMissingOrEmptySignature`, `refusesNonBase64Signature`, `refusesAVersionOver32Characters`, `refusesNotesOver4000Characters`, `refusesAMissingPlatformEntry`, `refusesNonJSON`, `refusesWrongTypes` (e.g. `sha256` as a number).
- [ ] **Step 2: Run** `scripts/test.sh --filter UpdateManifest`; expected FAIL. **Step 3: Implement** with `JSONSerialization` and explicit type checks per field (no clamping). **Step 4: Run**, expected pass. **Step 5: Commit** `feat(update): parse and strictly validate the signed feed`.

### Task 3: Signature verification, signing script, keypair

**Files:**
- Create: `Sources/UpdateCore/UpdateSignature.swift`, `Sources/UpdateCore/UpdatePublicKey.swift`, `packaging/updater/update_pub.pem`, `scripts/update-feed.sh`, `Tests/UpdateCoreTests/UpdateSignatureTests.swift`, `Tests/Fixtures/update/` (a TEST-ONLY keypair, `test_sign.key` and `test_pub.pem`, plus `README.md` saying so)

**Interfaces:**
- Produces: `public enum UpdateSignature { public static func sha256Hex(of file: URL) throws -> String; public static func verify(digestHex: String, signature: Data, publicKeyPEM: String) -> Bool; public static let publicKeyPEM: String }`. `scripts/update-feed.sh genkey` (writes `~/.config/loftline/update_sign.key` if absent, prints the base64 secret and the PKCS#1 public PEM from `openssl rsa -RSAPublicKey_out`); `scripts/update-feed.sh <tag> [--zip PATH] [--notes FILE]` writes `build/latest.json` for entry `macos-arm64` (`UPDATE_SIGN_KEY_FILE` selects the key; `gcodeChanged` is true when `samples/expected` or `Tests/Fixtures/golden` differ between the previous tag and this one, **false when there is no previous tag**).

- [ ] **Step 1: Failing tests** (create the test keypair first with `openssl genrsa -out test_sign.key 4096` and `-RSAPublicKey_out`; fixtures: a small `fixture.zip` signed by the real script): `signatureFromTheScriptVerifies` (run `scripts/update-feed.sh v9.9.9 --zip <fixture>` with `UPDATE_SIGN_KEY_FILE` set, parse the JSON with `UpdateManifest.parse`, verify with the test public key); `oneFlippedByteFails`; `aSignatureFromAnotherKeyFails`; `sha256HexMatchesOpenssl` (compare with `openssl dgst -sha256`); `manifestShaMatchesTheFile`; `noPreviousTagMeansGcodeUnchanged` (run the script in a temp git repo with no tags); `productionKeyMatchesTheCommittedPem` (`UpdateSignature.publicKeyPEM` equals the trimmed contents of `packaging/updater/update_pub.pem`).
- [ ] **Step 2: Run** `scripts/test.sh --filter UpdateSignature`; expected FAIL.
- [ ] **Step 3: Implement** `sha256Hex` (CryptoKit `SHA256` fed in 1 MiB chunks), `verify` (PEM to DER, `SecKeyCreateWithData` with `kSecAttrKeyTypeRSA` and `kSecAttrKeyClassPublic`, `SecKeyVerifySignature`), and `update-feed.sh` (port of `~/sites/hacking-bullet-heaven/tools/update_feed.sh`: python3 builds the JSON; asset `LoftLine-<tag>-macos-arm64.zip`; per-tag URL; `notes` truncated to 4000 characters).
- [ ] **Step 4: Generate the production key** locally with `scripts/update-feed.sh genkey` (private key stays in `~/.config/loftline/`, never printed to the log or committed), write the public PEM to `packaging/updater/update_pub.pem` and into `UpdatePublicKey.swift`. Record the base64 secret value for Task 8 (you set it; do not paste it anywhere else).
- [ ] **Step 5: Run** the filter again; expected pass. **Step 6: Commit** `feat(update): verify the signed archive and add the feed signing script` (key files under `Tests/Fixtures/update` are test-only and labelled).

### Task 4: State, controller and old-bundle cleanup (TDD)

**Files:**
- Create: `Sources/UpdateCore/UpdateStateStore.swift`, `Sources/LoftLineApp/Updates/UpdateController.swift`, `Sources/LoftLineApp/Updates/UpdateCleanup.swift`, `Tests/UpdateCoreTests/UpdateStateStoreTests.swift`, `Tests/LoftLineAppTests/UpdateControllerTests.swift`
- Modify: `Sources/LoftLineApp/Model/AppPreferences.swift` (add `autoCheckForUpdates = true`, key `loftline.pref.autoCheckForUpdates`, read in `init(defaults:)`, written in `save(to:)`)

**Interfaces:**
- Produces:
  ```swift
  public struct UpdateStateStore { public init(defaults: UserDefaults)
      public var lastCheck: Date?; public var skippedVersion: String?; public var lastPromptedVersion: String? }
  struct BundleInfo { var version: String; var channel: String; var bundleURL: URL }      // from Info.plist keys
  @MainActor final class UpdateController: ObservableObject {
      enum State: Equatable { case idle, checking, upToDate, available(UpdateEntry), downloading, readyToInstall(UpdateEntry),
                              installPending(relaunch: Bool), failed(String) }
      static let defaultFeedURL: URL
      @Published private(set) var state: State
      init(session: URLSession, store: UpdateStateStore, bundle: BundleInfo, publicKeyPEM: String, cacheDirectory: URL,
           autoCheckEnabled: @escaping () -> Bool,
           spawnHelper: @escaping (_ archive: URL, _ target: URL, _ pid: Int32, _ relaunch: Bool) -> Void, terminate: @escaping () -> Void)
      var canAutoCheck: Bool                      // channel == "release" && autoCheckEnabled() && no LOFTLINE_NO_UPDATE_CHECK
      func checkNow(userInitiated: Bool) async
      func download() async                       // available -> readyToInstall, or failed (and the file deleted)
      func installNow()                           // installPending(relaunch: true), then terminate()
      func installOnQuit()                        // installPending(relaunch: false)
      func skipVersion()
      func applicationWillTerminate()             // the only caller of spawnHelper
  }
  enum UpdateCleanup { static func removeOldBundles(besides app: URL) }   // deletes siblings named LoftLine.old-*
  ```

- [ ] **Step 1: Failing tests** (`URLProtocol` stub serves the feed and the archive; temp cache directory; test public key and fixture zip from Task 3): `checkFindsANewerVersion`; `sameOrOlderIsUpToDate`; `skippedVersionIsNotOffered`; `autoCheckHonoursThePreference` (`autoCheckEnabled` returning false makes `canAutoCheck` false on the release channel); `devChannelNeverAutoChecks` (`canAutoCheck == false`; a user-initiated check on dev reports that dev builds do not update); `feedOverrideIsHonouredOnlyOnDev`; `downloadRejectsAShaMismatchAndDeletesTheFile`; `downloadRejectsABadSignatureAndDeletesTheFile`; `verifiedDownloadIsReadyToInstall`; `translocatedCopyRefusesToInstall` (bundle URL contains `/AppTranslocation/`: `failed` message `Move LoftLine to Applications first`); `unwritableTargetRefusesToInstall`; `installNowOnlyTerminatesAndDoesNotSpawn` (`spawnHelper` not called, `terminate` called once); `installSpawnsOnlyWhenTheAppWillTerminate` (state `installPending`, then `applicationWillTerminate()` calls `spawnHelper` once with the helper arguments; a second call does nothing); `cancelledQuitKeepsThePendingInstall` (after `installNow()` with no `applicationWillTerminate`, state is still `installPending`); `automaticChecksAreThrottledToOncePerDay` (uses `store.lastCheck`); `cleanupRemovesOnlyOldSiblings` (siblings `LoftLine.old-123` removed, `LoftLine.app` and unrelated names kept); `stateStoreRoundTripsItsValues`; `appPreferencesPersistAutoCheck` (default true, false survives `save(to:)`/`init(defaults:)`).
- [ ] **Step 2: Run** `scripts/test.sh --filter Update`; expected compile failures. **Step 3: Implement** the types. Notes: `URLRequest` sets the `User-Agent`; the download streams to `cacheDirectory/LoftLine-<version>.zip` and hashes with `UpdateSignature.sha256Hex`; verification runs before `readyToInstall`; the production `spawnHelper` copies `Contents/Resources/updater.sh` to a temp file (mode 700) and runs it with `/bin/bash` and the Plan 3 arguments (`--archive --target <dir holding the app> --pid <pid> --relaunch 1|0`), detached with null standard streams.
- [ ] **Step 4: Run** the filter; expected pass. **Step 5: Commit** `feat(update): add the update controller, state store and old-bundle cleanup`.

### Task 5: UI and wiring

**Files:**
- Create: `Sources/LoftLineApp/Updates/UpdateSheet.swift`, `Sources/LoftLineApp/Updates/UpdateBanner.swift`, `Tests/LoftLineAppTests/UpdateUITests.swift`
- Modify: `Sources/LoftLineApp/App/LoftLineCommands.swift` (add `CommandGroup(after: .appInfo) { Button("Check for Updates…") }`), `Sources/LoftLineApp/Panels/PreferencesView.swift` (Section "Updates" in `GeneralPreferences`: Toggle "Check for updates automatically", and a "Last checked" line), `Sources/LoftLineApp/Panels/WelcomeView.swift` (show `UpdateBanner` when an update is available or pending), `Sources/LoftLineApp/App/LoftLineApp.swift` (launch: `UpdateCleanup.removeOldBundles`, a delayed auto-check, a 24 h timer; `applicationWillTerminate`: `UpdateController.shared.applicationWillTerminate()`), `Sources/LoftLineApp/Model/HelpTopics.swift` (`.preferences` body gains an "Updates and privacy" paragraph)

**Interfaces:**
- Consumes: `UpdateController` from Task 4. Produces: `UpdateController.shared` (production wiring: `.shared` session, `UserDefaults.standard`, `autoCheckEnabled` reading `PreferencesModel.shared.prefs.autoCheckForUpdates`, `Bundle.main` info, `~/Library/Caches/LoftLine/Updates`, the real helper spawn, `NSApp.terminate(nil)`); `UpdateSheet(controller:)`, `UpdateBanner(controller:)`.

- [ ] **Step 1: Failing tests** (`UpdateUITests`, following `AppUXRenderTests`): `sheetRendersEveryState` (host `UpdateSheet` in an `NSHostingView` for each `State`, no crash, non-zero fitting size); `sheetWarnsWhenGcodeChanged` (an `available` entry with `gcodeChanged: true` shows the text "post output changed" in its accessibility tree); `sheetOffersTheFourChoices` (Install and Restart, Install when I quit, Skip this version, Later); `preferencesHelpExplainsUpdateChecks` (`HelpTopic.preferences.body` contains `github.com`).
- [ ] **Step 2: Run** `scripts/test.sh --filter UpdateUI`; expected FAIL. **Step 3: Implement** the views and wiring. The sheet shows the notes and, if `gcodeChanged`, a line saying the post output changed in this release; one sheet per version (`lastPromptedVersion`); the app-menu item is disabled while a check or download runs; a failed manual check shows the reason, a failed automatic check only logs.
- [ ] **Step 4: Run** the filter, then the full `scripts/test.sh` (pass line with the baseline count plus the new tests). **Step 5: Manual check** on a `dev` build with `LOFTLINE_UPDATE_FEED_URL` pointing at a local fixture feed (served with `python3 -m http.server`): the menu item reports the dev-build message; with the override it finds the fixture version. **Step 6: Commit** `feat(update): add Check for Updates, the update sheet, banner and preference`.

### Task 6: Feed job, verify script, publish-after-verify

**Files:**
- Create: `scripts/verify-feed.sh`
- Modify: `.github/workflows/release.yml` (add the `feed` job), `scripts/check-release-workflow.sh`, `Tests/LoftLineAppTests/ReleaseScriptsTests.swift`

**Interfaces:**
- Produces: `scripts/verify-feed.sh <latest.json> <archive.zip> <public-pkcs1.pem>`: exit 0 only if the manifest `sha256` equals the archive's SHA-256 **and** the signature verifies (it converts the PKCS#1 PEM with `openssl rsa -RSAPublicKey_in -pubout` for `openssl dgst -sha256 -verify`).

- [ ] **Step 1: Failing tests:** `verifyFeedAcceptsAScriptMadeFeed` (feed from `update-feed.sh` with the test key); `verifyFeedRejectsAManifestShaThatDoesNotMatch`; `verifyFeedRejectsATamperedArchive`; and extend `check-release-workflow.sh` to assert: a `feed` job with `needs: macos` and `if: startsWith(github.ref, 'refs/tags/v')`; it decodes `UPDATE_SIGN_KEY` into `RUNNER_TEMP` and removes it in an `always()` step; `verify-feed.sh` runs **before** `gh release edit … --draft=false`; the downloaded files come from the draft release, not the build directory.
- [ ] **Step 2: Run** `scripts/test.sh --filter ReleaseScripts` and `scripts/check-release-workflow.sh`; expected FAIL.
- [ ] **Step 3: Implement** `verify-feed.sh` and the job: checkout (`fetch-depth: 0`); `gh release download "$TAG" --pattern '*.zip' --dir build`; notes from `gh release view "$TAG" --json body --jq .body > build/notes.md`; `scripts/update-feed.sh "$TAG" --notes build/notes.md`; `gh release upload "$TAG" build/latest.json --clobber`; re-download both into a fresh directory; `scripts/verify-feed.sh` on the re-downloaded files; only then `gh release edit "$TAG" --draft=false`; cleanup.
- [ ] **Step 4: Run** both checks; expected pass. **Step 5: Commit** `feat(release): sign, verify and only then publish the update feed`.

### Task 7: Docs

**Files:**
- Modify: `TESTING.md`, `README.md`, `docs/DECISIONS.md`, `docs/PARITY.md`

- [ ] **Step 1: TESTING.md** gets "Updates": the local-feed manual script from Task 5 Step 5, the tamper drill (a feed whose `sha256` is wrong is refused and the download deleted), and the cancelled-quit check (choose Install when I quit, quit, cancel at a save prompt, confirm nothing happened, quit for real, confirm the new version launches). README gets "Install and update" (download the zip from Releases, drag to Applications, the app checks daily and the toggle is in Settings). PARITY gets an "In-app updates" row.
- [ ] **Step 2: DECISIONS.md** appends `## Updates (2026-10-23)`: `updater-pattern` (rootkit-game's signed feed ported, why not Sparkle), `feed-signature` (bytes signed, PKCS#1 key, new keypair), `install-timing` (spawn from `applicationWillTerminate`, PID wait, two renames with `--recover`), `draft-first` (publish after verify), `dev-never-updates`.
- [ ] **Step 3: Commit** `docs: document the updater, its tests and its decisions`, then finish the branch with `ml:finishing-a-development-branch`.

### Task 8: Proof (outward-facing; each step needs your approval at the time)

**Files:** none.

- [ ] **Step 1: Secret.** You run `gh secret set UPDATE_SIGN_KEY -R seanperkins/loftline < <(base64 -i ~/.config/loftline/update_sign.key)` (the file is not echoed).
- [ ] **Step 2: Second rehearsal** on the final candidate: `gh workflow run release.yml -R seanperkins/loftline --ref main -f version=0.0.0`; then the release-candidate checklist from Plan 3 on the artifact. This build contains the updater, which the first rehearsal did not.
- [ ] **Step 3: Tag `v0.2.0`** (`git tag v0.2.0 && git push origin v0.2.0`). Expected: the workflow ends with a **published** release holding the zip and `latest.json`. Download the zip, install it into `/Applications`, open it; Help shows version 0.2.0 and the menu says Check for Updates… and reports up to date.
- [ ] **Step 4: Tag `v0.2.1`.** In the installed 0.2.0 choose Check for Updates…, Install and Restart. **The updater is proven only if** 0.2.0 finds 0.2.1, downloads it, verifies it, quits, is replaced and relaunches as 0.2.1, and no `LoftLine.old-*` remains beside it afterwards.
- [ ] **Step 5: Tamper drill.** On a scratch fork or a local fixture feed, serve a feed with a wrong `sha256`; the app refuses it, deletes the download and installs nothing. Record the results of Steps 3 to 5 in `docs/DECISIONS.md` under `updater-proof`.
