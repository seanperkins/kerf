# LoftLine Plan 1: rename and Kerf data migration

> **For agentic workers:** REQUIRED SUB-SKILL: Use ml:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename Kerf to LoftLine everywhere in code, scripts, CI and docs without changing one byte of G-code output, and carry a user's existing Kerf data over once.

**Architecture:** A one-shot scripted word-aware rename (not committed) in one green commit for code and scripts, one for docs. Then a small `LegacyKerfMigration` value type (injected directories, defaults and copier, so it is unit-testable) and a main-actor coordinator that runs it in `main.swift` after the CLI check and before the SwiftUI app starts.

**Tech Stack:** Swift 6 tools (Swift 5 language mode in app targets), SwiftPM only, swift-testing, zsh scripts. Build and test only through `scripts/build.sh`, `scripts/test.sh`, `scripts/check-samples.sh`.

**Spec:** `docs/specs/2026-10-23-loftline-rename-and-releases-design.md` (Part A, Phase 1 and "Migrating Kerf data"). The spec and these plans are untracked in `/Users/sean/sites/kerf`; Task 1 commits them to the branch. Plans 2 to 4 depend on this one.

## Global Constraints

- SwiftPM only: no `.xcodeproj`, no `xcodebuild`, no `.metal` files. Swift tools 6.0, macOS 14+, Apple Silicon.
- Tests use swift-testing (`import Testing`, `@Test`, `#expect`). Judge a run by its `Test run with N tests ... passed` line, never the exit code. Do not write a source file and run tests in the same shell command; if a run sits at 0% CPU, kill `swift-test` and `swiftpm-testing-helper` and retry once.
- Machine safety: Phase 1 must leave every golden byte-identical. `scripts/check-samples.sh` passes **without `--update`**; never weaken `GCodeValidator`.
- Conventional commits, one logical change each, build and tests green at each commit. No attribution lines in commit messages. Never commit on `main`: work in `.worktrees/loftline-rename` on branch `rename/loftline`.
- Mapping (spec): `Kerf`→`LoftLine`, `kerf-cli`→`loftline-cli`, `KerfApp`→`LoftLineApp`, `com.seanperkins.kerf`→`com.seanperkins.loftline` (`.project`, `.thumbnail` suffixes keep), `application/x-kerf+json`→`application/x-loftline+json`, `.kerf`→`.loftline`, `.kerftools`→`.loftlinetools`, `Application Support/Kerf`→`Application Support/LoftLine`, `kerf.*` defaults→`loftline.*`, `KERF_*`→`LOFTLINE_*`.
- Kept in Phase 1 (Phase 2 owns them): bare `KERF` sign text, `kerf_relief`, and the contents of `samples/`, `harness/projects/`, `Tests/Fixtures/`.
- No time or effort estimates.

## Review Focus

- A user whose old `kerf.groupByTool` is `true`: after migration the export still groups by tool (a lost key silently reorders G-code). Pinned in Task 4.
- First launch with an old `tools.json`: the library the app shows is the migrated one, not the seeded one (migration must precede `ToolLibraryModel.shared`). Pinned in Task 5.
- A copy interrupted halfway leaves no partial file, and Retry repairs it. Pinned in Task 4.
- A fresh install with no Kerf data anywhere: no crash, no empty folders, nothing to do. Pinned in Task 4.
- LoftLine already used before migrating (new files and new defaults exist): they are never overwritten. Pinned in Task 4.

---

### Task 1: Worktree, baseline, and the spec on the branch

**Files:**
- Create: `.worktrees/loftline-rename` (git worktree), `.tmp/loftline-baseline/` (scratch, ignored)
- Modify: `docs/specs/…`, `docs/plans/…` (added to the branch)

**Interfaces:**
- Produces: `.tmp/loftline-baseline/tests.txt` (the baseline `Test run with N tests` line) and `goldens.sha` (SHA-256 of every file under `samples/expected/`). Later tasks compare against both.

- [ ] **Step 1: Create the worktree.** `git check-ignore .worktrees` must print the path (it is in `.git/info/exclude`). Run `git worktree add .worktrees/loftline-rename -b rename/loftline` from `/Users/sean/sites/kerf`. Do all later work inside it.
- [ ] **Step 2: Record the baseline** in the worktree: `scripts/build.sh`; `scripts/test.sh 2>&1 | tee .tmp/loftline-baseline/tests.txt`; `scripts/check-samples.sh`; `find samples/expected -type f | sort | xargs shasum -a 256 > .tmp/loftline-baseline/goldens.sha`. Expected: build succeeds, the tests file contains one `Test run with N tests ... passed` line (note N, about 1,200), check-samples passes.
- [ ] **Step 3: Add the docs to the branch.** Copy `docs/specs/2026-10-23-loftline-rename-and-releases-design.md` and `docs/plans/2026-10-23-loftline-*.md` from the primary checkout into the worktree, then commit `docs: add the LoftLine rename, release and updater spec and plans`.

### Task 2: Scripted rename (code, scripts, CI)

**Files:**
- Create (uncommitted): `.tmp/loftline-rename/rename.py`
- Modify: every tracked text file outside the skip list; `git mv` for the paths below.

**Interfaces:**
- Produces: modules `LoftLineApp`, `LoftLineAppTests`; products `LoftLine` and `loftline-cli`; type prefix `LoftLine` (`LoftLineDocument`, `LoftLineProject`, `LoftLineFile`, `LoftLineIOError`, `LoftLineCLI`, `LoftLineCommands`, `LoftLineApp`, `LoftLineAppDelegate`); `ToolLibraryStore.supportDirectory` returns `…/Application Support/LoftLine`.

- [ ] **Step 1: Write `rename.py`** with a `--dry-run` default and `--apply`. Rules, applied in this order to text files only:
  - **Moves (`git mv`):** `Sources/KerfApp`→`Sources/LoftLineApp`; `Tests/KerfAppTests`→`Tests/LoftLineAppTests`; any tracked file whose basename contains `Kerf` (replace `Kerf` with `LoftLine`, including `Extensions/QuickLookThumbnail/KerfThumbnail.entitlements`); `.kerf`→`.loftline` for `samples/*.kerf`, `harness/projects/*.kerf`, `Tests/Fixtures/CADCore/document-v1.kerf`.
  - **Content:** `Kerf`→`LoftLine`; `KERF_`→`LOFTLINE_`; `kerftools`→`loftlinetools`; `com.seanperkins.kerf`→`com.seanperkins.loftline`; `kerf-`→`loftline-`; `.kerf` followed by a non-letter→`.loftline`; `kerf.` followed by a letter→`loftline.`; `__kerfNative`→`__loftlineNative`; `x-kerf+json`→`x-loftline+json`; lowercase `kerf` followed by an uppercase letter (camelCase such as `kerfProject`)→`loftline`.
  - **Never touched:** bare `KERF`, `kerf_relief`.
  - **Skip files (contents):** `docs/DECISIONS.md`, `docs/REVIEW-2026-10-20.md`, `docs/specs/2026-10-19-kerf-design.md`, `docs/specs/2026-10-23-*`, `docs/plans/*`, `samples/**`, `harness/projects/**`, `Tests/Fixtures/**`, `docs/images/**`, `Vendor/**`, binaries.
  - **Report:** per-rule and per-file counts, then every remaining lowercase `kerf` hit with file and line (these are prose and are read by a human, because kerf is also a woodworking word).
- [ ] **Step 2: Dry run, read the report, then `--apply`.** Expected: no `Kerf` left outside the skip list; the remaining-hit list is short and prose-only.
- [ ] **Step 3: Update names the script cannot know.** `scripts/bundle.sh` sample copy line becomes `cp samples/*.loftline samples/*.svg samples/*.dxf samples/*.stl …`; `scripts/check-samples.sh` glob becomes `samples/*.loftline` and its `--product` becomes `loftline-cli`; `SampleFilesTests` and `EndToEndSignTests` env names become `LOFTLINE_WRITE_SAMPLES` / `LOFTLINE_UPDATE_GOLDEN`. Verify with `git grep -n -E 'samples/\*\.kerf|--product kerf' ` (no output).
- [ ] **Step 4: Build and test.** `scripts/build.sh` then `scripts/test.sh 2>&1 | tee .tmp/loftline-baseline/tests-after.txt`. Expected: build succeeds; the `Test run with N tests ... passed` line has the **same N** as the baseline (`diff <(grep 'Test run with' …/tests.txt | sed 's/ in .*//') <(grep 'Test run with' …/tests-after.txt | sed 's/ in .*//')` prints nothing).
- [ ] **Step 5: Goldens unchanged.** `scripts/check-samples.sh` passes with no `--update`, and `find samples/expected -type f | sort | xargs shasum -a 256 | diff - .tmp/loftline-baseline/goldens.sha` prints nothing.
- [ ] **Step 6: Commit** `refactor: rename the package, targets, types, files and scripts from Kerf to LoftLine` (code, tests, scripts, `.github`, samples and harness renames).

### Task 3: Bundle identity and acceptance scan

**Files:**
- Verify: `scripts/bundle.sh` output, `Extensions/QuickLookThumbnail/Info.plist`

- [ ] **Step 1: Bundle.** `scripts/bundle.sh`; expected `Built dist/LoftLine.app`. Check: `plutil -lint dist/LoftLine.app/Contents/Info.plist` is OK; `plutil -p dist/LoftLine.app/Contents/Info.plist | grep -E 'loftline|LoftLine'` shows `CFBundleIdentifier` `com.seanperkins.loftline`, the type name `LoftLine Project`, extension `loftline`, UTI `com.seanperkins.loftline.project`, MIME `application/x-loftline+json`; `plutil -p dist/LoftLine.app/Contents/PlugIns/LoftLineThumbnail.appex/Contents/Info.plist` shows `com.seanperkins.loftline.thumbnail` and `QLSupportedContentTypes` `com.seanperkins.loftline.project`.
- [ ] **Step 2: Bundled export matches the golden.** `dist/LoftLine.app/Contents/MacOS/LoftLine export samples/sign.loftline --post generic-grbl-mm --builtin-only --out .tmp/loftline-bundle-out --quiet`, then `diff .tmp/loftline-bundle-out/sign.nc samples/expected/generic-grbl-mm/sign.nc` prints nothing.
- [ ] **Step 3: Acceptance scan.** `git grep -n -i kerf | grep -v -E '^(docs/DECISIONS.md|docs/REVIEW-2026-10-20.md|docs/specs/|docs/plans/|samples/|harness/projects/|Tests/Fixtures/|docs/images/)'`. Every remaining line must be one of: bare `KERF` artwork selectors or fixtures (`harness/scenarios/main.json`, `reel-readme.json`, the text constants in `SampleFilesTests` and `EndToEndSignTests`), `kerf_relief` in `SampleFilesTests`, or a prose use of the word. Anything else is a missed rename: fix it and repeat Steps 4 and 5 of Task 2. Paste the final exception list into the pull request description.
- [ ] **Step 4: Clean up.** `dist/` is gitignored; delete `.tmp/loftline-bundle-out`.

### Task 4: `LegacyKerfMigration` (TDD)

**Files:**
- Create: `Sources/LoftLineApp/Model/LegacyKerfMigration.swift`, `Tests/LoftLineAppTests/LegacyKerfMigrationTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct LegacyKerfMigration {
      enum Outcome: Equatable { case notNeeded, completed, failed(String) }
      static let flagKey = "loftline.migratedFromKerf"      // stored "done" or "skipped"
      init(oldSupport: URL, newSupport: URL, readOldDefaults: @escaping () -> [String: Any]?,
           defaults: UserDefaults, copy: @escaping (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) })
      func run() -> Outcome
      func markSkipped()
      static func standard() -> LegacyKerfMigration   // Task 5
  }
  ```

- [ ] **Step 1: Write the failing tests** in `LegacyKerfMigrationTests` (`@Suite struct`, each test builds temp dirs under `FileManager.default.temporaryDirectory/"loftline-tests-<UUID>"` and a `UserDefaults(suiteName: "loftline-tests-<UUID>")`): `copiesToolsJsonWhenTheDestinationIsMissing`; `neverOverwritesAnExistingDestinationFile` (new `tools.json` keeps its bytes); `skipsTheRecoveryDirectory`; `renamesProjectAndToolExchangeExtensions` (`templates/a.kerf`→`a.loftline`, `x.kerftools`→`x.loftlinetools`); `copiesEveryKerfDefaultsKeyByPrefix` (old domain with `kerf.groupByTool: true`, `kerf.pref.defaultUnits`, `kerf.inspector.expanded.x`, `NSWindow Frame Kerf.welcome` ends as `loftline.groupByTool == true`, `loftline.pref.defaultUnits`, `loftline.inspector.expanded.x`, `NSWindow Frame LoftLine.welcome`); `doesNotOverwriteAnExistingNewDefault`; `aFailedCopyLeavesNoPartialFileAndNoFlag` (injected `copy` throws after writing half of the second file: outcome `.failed`, the destination has no file or `.migrating` leftover for it, flag is nil); `retryAfterAFailureCompletes` (same fixture, a working `copy`, outcome `.completed`, all files present, flag `"done"`); `aFreshInstallIsNotNeeded` (no old directory, `readOldDefaults` returns nil: outcome `.notNeeded`, no new directory created, flag `"done"`); `aSecondRunIsNotNeeded`; `markSkippedStopsFutureRuns` (after `markSkipped()` flag is `"skipped"` and `run()` is `.notNeeded`).
- [ ] **Step 2: Run to verify failure.** `scripts/test.sh --filter LegacyKerfMigration`. Expected: compile error, `LegacyKerfMigration` not defined.
- [ ] **Step 3: Implement** the type. Behaviour: if the flag is set return `.notNeeded`. Walk `oldSupport` (skip a top-level `Recovery`), map extensions `kerf`→`loftline` and `kerftools`→`loftlinetools`, skip any existing destination, and for each file call `copy(src, dest + ".migrating")` then `moveItem` to the final name; on any error remove the temporary file and return `.failed(error.localizedDescription)` without touching the flag. Then copy defaults: every key with prefix `kerf.` becomes `loftline.` plus the rest, and `NSWindow Frame Kerf.` becomes `NSWindow Frame LoftLine.`, each only if the destination key is unset. Write the flag `"done"` **last**.
- [ ] **Step 4: Run to verify pass.** Same command. Expected: all `LegacyKerfMigration` tests pass.
- [ ] **Step 5: Commit** `feat(app): add the one-time Kerf data migration`.

### Task 5: Coordinator, launch wiring, tool library reload (TDD)

**Files:**
- Create: `Sources/LoftLineApp/Model/LegacyMigrationCoordinator.swift`, `Tests/LoftLineAppTests/LegacyMigrationCoordinatorTests.swift`
- Modify: `Sources/LoftLineApp/main.swift`, `Sources/LoftLineApp/App/LoftLineApp.swift` (`applicationDidFinishLaunching`), `Sources/LoftLineApp/Model/ToolLibraryModel.swift`, `Sources/LoftLineApp/Model/LegacyKerfMigration.swift` (add `standard()`)

**Interfaces:**
- Consumes: `LegacyKerfMigration` from Task 4.
- Produces:
  ```swift
  @MainActor final class LegacyMigrationCoordinator {
      enum Choice { case retry, continueWithout }
      static let shared: LegacyMigrationCoordinator
      private(set) var failure: String?
      init(migration: LegacyKerfMigration, reloadTools: @escaping () -> Void)
      func runAtLaunch()                         // no-op when LOFTLINE_NO_MIGRATION=1
      @discardableResult func resolve(_ choice: Choice) -> LegacyKerfMigration.Outcome?
      func presentFailureIfNeeded()              // NSAlert: Retry / Continue without importing
  }
  ToolLibraryModel.reload()                      // re-reads the store into `library`
  ```

- [ ] **Step 1: Write the failing tests:** `failureIsRecordedThenRetryClearsItAndReloadsTools` (injected migration whose first `run` fails, second succeeds; `reloadTools` called once); `continueWithoutWritesSkippedAndClearsTheFailure`; `noMigrationEnvVarSkipsTheRun`; `toolLibraryReloadPicksUpAFileWrittenAfterInit` (store pointing at a temp file; write tools after init; `reload()`; `library.tools` matches); `mainSwiftOrdersTheStartup` (read `Sources/LoftLineApp/main.swift` via `#filePath`; the offsets of `runIfRequested`, `LegacyMigrationCoordinator.shared.runAtLaunch()` and `LoftLineApp.main()` are strictly increasing, which pins "after the CLI check, before the app builds the tool library").
- [ ] **Step 2: Run to verify failure.** `scripts/test.sh --filter LegacyMigrationCoordinator`. Expected: compile errors.
- [ ] **Step 3: Implement** the coordinator, `ToolLibraryModel.reload()` (publish the loaded library and bump `revision`), `LegacyMigrationCoordinator.shared` (built from `.standard()` with `reloadTools: { ToolLibraryModel.shared.reload() }`), `LegacyKerfMigration.standard()` (old dir is the sibling `Application Support/Kerf`, new dir `ToolLibraryStore.supportDirectory`, old defaults `UserDefaults.standard.persistentDomain(forName: "com.seanperkins.kerf")`, destination `.standard`). In `main.swift` insert `LegacyMigrationCoordinator.shared.runAtLaunch()` between the CLI check and `LoftLineApp.main()`. In `applicationDidFinishLaunching` call `LegacyMigrationCoordinator.shared.presentFailureIfNeeded()` after the existing recovery start.
- [ ] **Step 4: Run to verify pass.** Same filter, expected all pass; then the full `scripts/test.sh`, expected the pass line with the baseline N plus the new tests.
- [ ] **Step 5: Commit** `feat(app): run the Kerf migration before the app loads, with Retry or Continue on failure`.

### Task 6: Gadget alias (TDD)

**Files:**
- Modify: `Sources/LoftLineApp/Model/Gadgets/GadgetAPI.swift`, `Tests/LoftLineAppTests/GadgetTests.swift`

- [ ] **Step 1: Failing test** `legacyKerfNamespaceIsAnAliasOfLoftline` in the gadget run suite using its `run(_:)` helper: `try run(#"kerf.log("a"); loftline.log("b");"#)`, then `#expect(r.log.joined(separator: "\n").contains("a") && r.log.joined(separator: "\n").contains("b"))`.
- [ ] **Step 2: Run** `scripts/test.sh --filter GadgetScriptTests`. Expected: FAIL (`kerf` is not defined).
- [ ] **Step 3: Implement** by adding `var kerf = loftline;` in the prelude directly after the `})(__loftlineNative);` line, with a comment that it is a one-release alias for scripts written before the rename.
- [ ] **Step 4: Run** the same filter, expected pass. **Step 5: Commit** `feat(gadgets): keep kerf as an alias of loftline for one release`.

### Task 7: Docs, decision entry, and finish

**Files:**
- Modify: `docs/DECISIONS.md` (append), `TESTING.md`, `README.md`, `AGENTS.md`, `docs/PARITY.md` (rename pass from Task 2 already applied; review the diff)

- [ ] **Step 1: Docs commit.** Review `git diff` of the docs from Task 2's script; commit `docs: rename Kerf to LoftLine in the README, AGENTS.md, TESTING.md and PARITY`.
- [ ] **Step 2: Append a `## Rename to LoftLine (2026-10-23)` entry to `DECISIONS.md`** in the file's existing style (`- **key — headline.** …`): `rename-scope` (what changed, what stays: history docs, sample artwork until Phase 2), `rename-migration` (prefix rule for every `kerf.*` key, `kerf.groupByTool` orders G-code, copy never overwrites, flag last, Retry or Continue, the gadget `kerf` alias for one release), `rename-startup-order` (migration after the CLI check, before the app builds the tool library). Add a TESTING.md section "Migrating from Kerf": create `~/Library/Application Support/Kerf/tools.json` and `defaults write com.seanperkins.kerf kerf.groupByTool -bool true`, launch LoftLine, expect the tools and the setting to be present, and re-launch to see nothing repeats. After you have checked your data came across, delete the old `Kerf.app` by hand: it stays installed and keeps registering `.kerf`.
- [ ] **Step 3: Full gate.** `scripts/build.sh`, `scripts/test.sh` (pass line, count above baseline), `scripts/check-samples.sh` with no `--update`, goldens SHA diff empty. Commit `docs: record the LoftLine rename decisions and the migration test script`.
- [ ] **Step 4: Finish the branch** with `ml:finishing-a-development-branch` (PR from `rename/loftline` to `main`). Do not merge before Plan 2 starts unless told to.
