# LoftLine Plan 2: brand kit, app icon and sample content

> **For agentic workers:** REQUIRED SUB-SKILL: Use ml:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the LoftLine icon and brand kit in the repo, change the sample sign from "KERF" to "LOFTLINE" through its generators with every golden reviewed, and re-record the README images.

**Architecture:** The sign artwork is generated in code (`SampleFilesTests`, `EndToEndSignTests`), so the text is changed in the generators and the files are regenerated, never hand-edited. The five harness projects become a derived, tested patch set on the new sample so they cannot rot again. Brand SVGs are the source of truth; the Python generator that drew them stays outside the repo.

**Tech Stack:** Swift 6 tools, swift-testing, zsh, `scripts/ui.sh` and `scripts/reel.sh` (needs `ffmpeg`), headless Chrome for the social card.

**Spec:** `docs/specs/2026-10-23-loftline-rename-and-releases-design.md` (Phase 2, decision 5). **Depends on Plan 1** being merged (names below are post-rename: `Sources/LoftLineApp`, `.loftline`, `LOFTLINE_*`).

## Global Constraints

- Same as Plan 1: SwiftPM only; swift-testing; judge test runs by the `Test run with N tests ... passed` line; conventional commits, one logical change each, green at each commit; no attribution lines; never commit on `main`: new worktree `.worktrees/loftline-content`, branch `content/loftline`.
- Machine safety: every changed golden G-code file is reviewed line by line. Only the sign programs may change; `faced-board` must not. Never weaken `GCodeValidator`.
- Regenerate, do not hand-edit: samples via `LOFTLINE_WRITE_SAMPLES=1 scripts/test.sh --filter SampleFiles`; end-to-end fixture and goldens via `LOFTLINE_UPDATE_GOLDEN=1 scripts/test.sh --filter EndToEndSign`; sample goldens via `scripts/check-samples.sh --update`.
- Brand (from the spec): Cut Path direction, "LoftLine" wordmark Regular, graphite `#111317`, lime `#C6EE3A`, IBM Plex Sans and Mono for brand type (the app UI keeps the system font), brand colours never on the canvas. Final kit source: `docs/mockups/loftline-brand/assets/r4/` in the primary checkout (untracked there).
- Never commit the Vectric `*.exe` installers; the round 1 to 5 HTML mockups stay out of git.
- No time or effort estimates.

## Review Focus

- The sign text now has eight letters: it must fit inside the 22 x 10 in outline and clear the bottom panel and the hanging hole, or the V-carve overlaps a drilled hole. Pinned in Task 2.
- The harness variants share shape and operation order with the sample; a regenerated sample with a different operation order would silently apply a patch to the wrong operation. Pinned in Task 4.
- `EndToEndSignTests` is not serialized and writes its fixture on every call under `LOFTLINE_UPDATE_GOLDEN`; concurrent writes can corrupt it. Pinned in Task 3.
- A missing icon must fail loudly: a bundle built without `Resources/AppIcon.icns` ships the generic icon. Pinned in Task 1.
- Stale text in the README ("KERF text selected", "about 13 minutes") after the sample changes. Pinned in Task 6.

---

### Task 1: Brand kit, `AppIcon.icns` and the brand README

**Files:**
- Create: `Resources/AppIcon.icns`, `docs/brand/` (copy from `…/assets/r4/`: `wordmark-light.svg`, `wordmark-dark.svg`, `mark-*.svg`, `mark-small-*.svg`, `lockup-h-*.svg`, `lockup-v-*.svg`, `icon.svg`, `icon-small.svg`, `doc-icon.svg`, `editable/*.svg`, `editable/*.pdf`, `png/icon-{16,32,64,128,256,512}.png`, `png/doc-icon-512.png`), `docs/brand/README.md`
- Modify: `scripts/bundle.sh`
- Test: `Tests/LoftLineAppTests/BrandAssetsTests.swift`

**Interfaces:**
- Produces: `Resources/AppIcon.icns` (copied by `bundle.sh` to `Contents/Resources/AppIcon.icns`, already referenced by `CFBundleIconFile`); `docs/brand/README.md` with the palette, type, clear-space and minimum-size rules and the social-preview recipe (Task 6 fills the recipe).

- [ ] **Step 1: Failing test** `BrandAssetsTests` (locate the repo root with `#filePath` as `SampleFilesTests` does): `appIconExistsAndIsAnIcns` (file `Resources/AppIcon.icns` exists, begins with the bytes `icns`); `brandKitHasTheMasters` (every file named above exists under `docs/brand`); `everyBrandSVGIsWellFormedXML` (each `.svg` parses with `XMLParser`).
- [ ] **Step 2: Run** `scripts/test.sh --filter BrandAssets`. Expected: FAIL, files missing.
- [ ] **Step 3: Add the files** (copy only; do not copy `loftline-editable.zip` or the 1024 px PNGs) and write `docs/brand/README.md`: palette tokens and the contrast table values from the spec, type pairing, clear space (one quarter of the mark's height), minimum sizes (mark 16 px, two-pass drawing below 48 px; lockup 100 px wide), the colour do/do-not list, and a note that the SVG masters are the source of truth.
- [ ] **Step 4: Make the icon mandatory.** In `scripts/bundle.sh` replace the `[[ -f Resources/AppIcon.icns ]] && cp …` line with `cp Resources/AppIcon.icns $APP/Contents/Resources/AppIcon.icns` (`set -e` then fails the build when it is missing).
- [ ] **Step 5: Verify.** `scripts/test.sh --filter BrandAssets` passes; `scripts/bundle.sh` prints `Built dist/LoftLine.app`; `test -f dist/LoftLine.app/Contents/Resources/AppIcon.icns`; `sips -g pixelWidth Resources/AppIcon.icns` reports 1024.
- [ ] **Step 6: Commit** `feat(brand): add the LoftLine icon and brand kit` (icon, kit, README, test, `bundle.sh`).

### Task 2: Sample generator text, regenerate samples, review

**Files:**
- Modify: `Tests/LoftLineAppTests/SampleFilesTests.swift` (text constant and doc comment in `signSVG()`; both `kerf_relief` solid names; sign project name strings), `samples/sign.loftline`, `samples/sign.svg`, `samples/sign.tap`, `samples/relief.stl` (regenerated, not edited)

- [ ] **Step 1: Record the starting point** with `git rev-parse HEAD > .tmp/old-sample-commit` (Task 4 needs the old sample). Then add the failing test to `SampleFilesTests`: `signTextIsLoftlineAndFitsTheSign` — build the sign shapes the way `signSVG()` does and `#expect` the text shape's bounds lie inside `Rect2(x: 1.5, y: 3.8, width: 21, height: 4)` (clear of the panel at y 2 to 3.5 and of the hole at x 12, y 10) and that its name is `"LOFTLINE"`.
- [ ] **Step 2: Run** `scripts/test.sh --filter SampleFiles`. Expected: FAIL on the name and bounds (text is still "KERF").
- [ ] **Step 3: Change the generator.** Set the `TextOutliner().shape(for:)` text to `"LOFTLINE"` and the doc comment to match; if the bounds test fails, reduce `size` (2.5) until it passes and note the value; rename `solid kerf_relief`/`endsolid kerf_relief` to `loftline_relief`.
- [ ] **Step 4: Regenerate.** `LOFTLINE_WRITE_SAMPLES=1 scripts/test.sh --filter SampleFiles`; then `git diff --stat samples/`. Expected: only `sign.loftline`, `sign.svg`, `sign.tap`, `relief.stl` changed (the `faced-board` sample unchanged).
- [ ] **Step 5: Review the diff.** `samples/sign.svg` opened as an image shows LOFTLINE inside the sign; `samples/sign.tap` changes only in the V-carve of the text (look for the header, tool, safe-Z and end-of-program lines unchanged); `relief.stl` changes only line 1 and the last line. Run `scripts/test.sh --filter SampleFiles` without the env: passes.
- [ ] **Step 6: Commit** `feat(samples): the sample sign says LOFTLINE` (generator and regenerated samples). Goldens are not touched yet.

### Task 3: End-to-end fixture, serialized and regenerated

**Files:**
- Modify: `Tests/LoftLineAppTests/EndToEndSignTests.swift`, `Tests/Fixtures/e2e/sign.svg`, `Tests/Fixtures/golden/sign-materialTop.tap`, `Tests/Fixtures/golden/sign-spoilboard.tap`

- [ ] **Step 1: Serialize the suite.** Add `.serialized` to the suite attribute; change `makeSignSVG()`'s `"KERF"` to `"LOFTLINE"` and its comment, with the same `size` as Task 2.
- [ ] **Step 2: Run** `scripts/test.sh --filter EndToEndSign`. Expected: FAIL (fixture and goldens are the old text).
- [ ] **Step 3: Regenerate once.** `LOFTLINE_UPDATE_GOLDEN=1 scripts/test.sh --filter EndToEndSign`. Review `git diff Tests/Fixtures/e2e/sign.svg` first (the text paths changed, nothing else), then both `.tap` diffs (text V-carve only; header, Z-zero handling for material-top and spoilboard modes and the end block unchanged).
- [ ] **Step 4: Run without the env** `scripts/test.sh --filter EndToEndSign`: passes in both Z-zero modes.
- [ ] **Step 5: Commit** `test(e2e): the end-to-end sign says LOFTLINE, with the suite serialized`.

### Task 4: Harness projects derived from the sample, and the scenario selectors

**Files:**
- Create: `Tests/LoftLineAppTests/HarnessProjectsTests.swift`
- Modify: `harness/projects/{sign-loose,sign-overcut,sign-pause,reel-sign,reel-loose}.loftline` (regenerated), `harness/scenarios/main.json`, `harness/scenarios/reel-readme.json`, any other scenario that selects the sign text by name (`git grep -n '"KERF"' harness/scenarios`)

**Interfaces:**
- Produces: `HarnessProjectsTests.patches: [(file: String, apply: (inout [String: Any]) -> Void)]` encoding exactly the five variants, by JSON path into the decoded sample:
  - `sign-loose`: `operations[3].profile._0.params.tabs.isEnabled = false`
  - `sign-overcut`: `operations[3].profile._0.params.depth.cutDepth = 0.77`
  - `sign-pause`: `operations[0].pocket._0.setup.pauseAfter = {"isOptionalStop": false, "message": "Flip the part and clamp the far edge"}`
  - `reel-sign`: remove `operations[2]` (the drill operation)
  - `reel-loose`: `reel-sign` then `operations[2].profile._0.params.tabs.isEnabled = false`

- [ ] **Step 1: Self-check the patches against the old files first.** Save the old sample with `git show $(cat .tmp/old-sample-commit):samples/sign.loftline > .tmp/old-sign.loftline`, apply each patch to it with `JSONSerialization`, and compare to the variant as it was at that commit (`git show $(cat .tmp/old-sample-commit):harness/projects/<file>`) with `NSDictionary.isEqual`. Expected: all five equal. This proves the patch list is the whole difference.
- [ ] **Step 2: Write the test** `harnessProjectsAreTheSampleWithOnePatchEach`: for each patch, load `samples/sign.loftline`, apply it, and `#expect` equality with `harness/projects/<file>` (as `[String: Any]`). With `LOFTLINE_WRITE_SAMPLES=1` it writes the patched JSON (`.prettyPrinted, .sortedKeys`) instead of comparing. Also `patchesTargetTheExpectedOperations`: `operations[2]` of the sample has a `drill` key, `operations[3]` a `profile` key, `operations[0]` a `pocket` key.
- [ ] **Step 2b: Run** `scripts/test.sh --filter HarnessProjects`. Expected: FAIL (variants still carry the old text).
- [ ] **Step 3: Regenerate** `LOFTLINE_WRITE_SAMPLES=1 scripts/test.sh --filter HarnessProjects`, then the same filter without the env: passes.
- [ ] **Step 4: Selectors.** Replace `"KERF"` with `"LOFTLINE"` in the scenario selectors found above. Run `scripts/test.sh --filter HarnessScenario` and `scripts/ui.sh main --light`; expected: the run succeeds and the PNG shows the text shape selected.
- [ ] **Step 5: Commit** `test(harness): derive the harness projects from the sample and select LOFTLINE`.

### Task 5: Sample goldens

**Files:**
- Modify: `samples/expected/*/sign.nc` (three posts)

- [ ] **Step 1: Run the check, expect failure.** `scripts/check-samples.sh`; expected FAIL for the three sign programs only (`faced-board` passes).
- [ ] **Step 2: Update.** `scripts/check-samples.sh --update`; `git diff --stat samples/expected`: exactly the three `sign.nc` files. Review each diff: only text V-carve moves change; for each post the header, units, preamble, tool changes, safe-Z retracts before XY rapids, and the program end are untouched.
- [ ] **Step 3: Verify.** `scripts/check-samples.sh` passes with no `--update`; full `scripts/test.sh` shows the pass line.
- [ ] **Step 4: Commit** `test(samples): regenerate the sign programs for the LOFTLINE text`.

### Task 6: README images, README text and the social preview

**Files:**
- Modify: `docs/images/{hero-light,hero-dark,step-1,step-2,step-3,step-4}.png`, `docs/images/{import,pause,preflight,preview,variables}.{gif,mp4}`, `docs/images/social-preview.png`, `README.md`, `docs/UI-HARNESS.md`, `docs/brand/README.md`
- Create: `docs/brand/social-preview.html`

- [ ] **Step 1: Stills and clips.** With `ffmpeg` installed, `scripts/reel.sh all` (the `reel-readme` scenario writes the hero and step PNGs). Expected: every file under `docs/images` listed above is rewritten; open the hero and step images and the GIFs and check the sign says LOFTLINE and the window title and menus say LoftLine.
- [ ] **Step 2: Social card.** Render a fresh 3D render of the new sign (the preview window via `scripts/ui.sh preview` capture, saved as `.tmp/sign-3d.png`). `docs/brand/social-preview.html` is a 1280 x 640 page: graphite `#111317` background, the `lockup-h-dark.svg` lockup top left, the tagline "CAD/CAM for CNC routers, native on the Mac" in IBM Plex Sans, the chips `design → toolpaths` / `3D preview → G-code` in IBM Plex Mono top right, the render along the bottom. Capture with headless Chrome at exactly 1280 x 640 to `docs/images/social-preview.png`. Write the exact command and the font note into `docs/brand/README.md` so the next image is reproducible.
- [ ] **Step 3: README.** Change "(`samples/sign.loftline`) … about 13 minutes of machine time" to the new sample's time (read it from the app's time estimate or `loftline-cli`; do not guess), the `step-1` alt text to "LOFTLINE text selected", and any remaining "Kerf's" image alt text; update the `docs/UI-HARNESS.md` project example path if it still names a `.kerf` file.
- [ ] **Step 4: Verify.** `git grep -n -i kerf -- README.md docs/UI-HARNESS.md docs/brand` prints nothing; the README renders (open it) with no broken images.
- [ ] **Step 5: Commit** `docs(images): re-record the README images and social preview for LoftLine`.

### Task 7: Decision entry and finish

**Files:**
- Modify: `docs/DECISIONS.md`, `docs/PARITY.md` (only if the sign or icon is mentioned)

- [ ] **Step 1: Append** a `## LoftLine sample content (2026-10-23)` entry in the file's style: `sign-text` (generators, not hand edits; what regenerates what), `harness-derived` (variants are patches on the sample, tested), `brand-kit` (what is committed where, what is not), `social-card` (recipe, no generator).
- [ ] **Step 2: Full gate.** `scripts/build.sh`, `scripts/test.sh` (pass line), `scripts/check-samples.sh` with no `--update`.
- [ ] **Step 3: Commit** `docs: record the LoftLine sample, harness and brand decisions`, then finish the branch with `ml:finishing-a-development-branch`.
