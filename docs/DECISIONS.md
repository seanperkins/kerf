# Decisions log (append-only)

- **scaffold** — Toolpath moves are in machine coordinates; `MachineCoordinates` (CAMCore) is the
  single material→machine mapping for XY origin and Z-zero mode. Generators think in depth
  below the material top.
- **scaffold** — Document geometry uses a fixed material frame (lower-left = 0,0). The XY origin
  choice only affects G-code, so moving the origin never moves the design.
- **scaffold** — Safe Z and home Z are stored as heights above the material top (VCarve style);
  `home` XY is in machine coordinates.
- **scaffold** — Arcs in `Move` carry an absolute machine-XY centre; the post converts to
  incremental IJ (Mach4 default) or linearises.
- **scaffold** — Drilling is emitted as explicit G0/G1 pecks (no G81/G83) for portability.
- **scaffold** — CGeom exposes a C API (not C++ interop) so Swift targets build without
  `-cxx-interoperability-mode`. Boost dependency trimmed to the Voronoi headers +
  `boost/cstdint.hpp` + Boost.Config.
- **scaffold** — Voronoi input is snapped to an integer grid (`scale`, default 10000/unit);
  edges come back pre-sampled with inscribed radius so V-carve does not need parabola math.
- **scaffold** — Seeded tool library uses fixed UUIDs (`00000000-0000-4000-8000-00000000000N`)
  so documents referencing seeded tools stay valid.
- **scaffold** — Generic GRBL profile uses `M0` (pause) for tool changes since GRBL 1.1 has no M6.
- **scaffold** — Validator checks the toolpath XY *extent* against travel (the job origin's
  position on the bed is unknown to Kerf).
- **scaffold** — Swift targets use Swift 5 language mode under tools-version 6.0 to avoid
  strict-concurrency friction; public model types are still `Sendable`.
- **post** — Coordinates use fixed `decimals` (4 inch / 3 mm), feeds `feedDecimals`; numbers are
  formatted with the POSIX locale and "-0.0000" is normalised to "0.0000".
- **post** — Modal output: repeated G0/G1 words, unchanged axes and unchanged F are suppressed.
  Arcs always state G2/G3 plus X and Y (Mach4 full circles need them). Any non-motion line
  (spindle, dwell, tool change) makes the next motion restate its G-word; after a tool change
  position and feed are forgotten, so the first cut always restates F.
- **post** — Safety net in the writer: an XY rapid starting below safe Z first emits `G0 Z<safe>`;
  a rapid whose target is below safe Z is split into XY at safe Z then a Z-only rapid.
- **post** — Tool change sequence: retract to safe Z, profile `toolChange` lines (also for the
  first tool, so GRBL pauses with M0 to load it), optional `G43 H<n>`, `G0 Z<safe>`, spindle
  on, `G4 P<seconds>` (seconds — Mach4/GRBL default). Spindle is restarted (with dwell) when the
  RPM changes within the same tool. Spindle speed outside the profile's RPM range throws.
- **post** — `post` emits toolpaths in the given order; `postCombined` groups by tool
  (`ToolpathOrdering.groupedByTool`) first. A tool change happens when the tool *id* changes.
- **post** — Comments are forced to ASCII (° → " deg", diacritics stripped) and template
  values substituted into comments have parentheses turned into brackets.
- **post** — Helical arcs are emitted as G2/G3 with Z when `helicalArcs`; otherwise (or with
  `arcOutput = .linearize`) arcs are linearised to `arcTolerance`.
- **post** — Header time estimate (`PostTimeEstimator`, public) = feed length/feed + rapid
  length/`rapidRate` + dwells + spindle dwell per spindle start; no acceleration model. Kept in
  PostCore so the post does not depend on the preview workstream's estimator.
- **post** — Golden programs are inline raw-string literals in `PostGoldenTests.swift` (no test
  resources, so Package.swift stays untouched).
- **post** — GCodeValidator rules (shared by toolpath and G-code checks via `MotionChecker`):
  error = travel span > machine travel (arcs sampled via I/J), Z below material bottom minus
  `limits.maxSpoilboardCut` (both Z-zero modes), XY rapid with Z below the material top, feed
  move below the material top with the spindle off, feed move without F or with F <= 0, S
  outside min/max RPM, arc start/end radius mismatch, arc without I/J/R. Warnings = XY rapid
  below safe Z but above the material, rapid plunge below the top, XY rapid before Z is known,
  feed above `maxFeed`, G91, units differing from the profile, no G20/G21, no M30/M2,
  unparseable text. Repeats of the same rule are collapsed into one issue "(N more)". G-code
  is checked in the units it declares (G20/G21), defaulting to the profile's.
- **cad-io** — SVG import places the SVG page's lower-left corner at document (0,0) and flips Y.
  User units without a physical size are CSS px (96/in); `preserveAspectRatio` (meet/slice/none)
  is honoured. Top-level `<g>` elements (and Inkscape layers) become layers; loose top-level
  elements go to an "SVG Import" layer. `<text>`/`<image>` are skipped with a warning.
- **cad-io** — Circular SVG arcs stay `.arc` segments (split at 180°); elliptical/rotated arcs
  become cubics. Quadratics become cubics everywhere (SVG, CoreText, EPS).
- **cad-io** — SVG export page spans `min(0, bounds.min)…bounds.max` with physical width/height
  in document units, so designs in the material frame round-trip exactly.
- **cad-io** — DXF without `$INSUNITS` falls back to `$MEASUREMENT`; with neither, values are read
  as document units and a warning is returned. Loose open entities on the same layer are joined
  (0.0005 in / 0.01 mm) so imported outlines are usable as closed vectors.
- **cad-io** — DXF SPLINEs with control points are evaluated (rational de Boor) and sampled to a
  polyline; fit-point-only splines become Catmull-Rom cubics. Block INSERTs are expanded
  (layer-0 entities inherit the insert's layer); MINSERT arrays, TEXT, HATCH, DIMENSION are skipped
  with a warning. OCS extrusion Z=-1 mirrors X.
- **cad-io** — DXF export is R12 ASCII: one POLYLINE with bulges per path (cubics flattened at
  0.0005 in / 0.01 mm), full circles as CIRCLE, layer table with nearest basic ACI colour.
- **cad-io** — Text size is the CAP HEIGHT in document units (what is measured on the finished
  sign); the CoreText point size is derived from the font's cap height. Unknown fonts throw
  `TextOutliner.TextError.fontNotFound` instead of silently substituting. Glyph contours are
  normalised (outer CCW, holes CW) by nesting depth; overlapping contours (some variable fonts)
  are not unioned.
- **cad-io** — `.kerf` versioning lives in `KerfFile` (CADCore): JSON-level migrations keyed by
  the version they upgrade from, newer files rejected, missing `formatVersion` = 1.
  `DocumentFile` writes `{formatVersion, document, operations: [], tools: []}` so a design-only
  file opens as a `KerfProject`. `KerfFile.currentVersion` must track
  `KerfProject.currentFormatVersion`; the app should decode projects via
  `KerfFile.decode(KerfProject.self, from:)` to get migrations.
- **cad-io** — Test fixtures live in `Tests/Fixtures/CADCore/` (outside any target, loaded via
  `#filePath`) so no `Package.swift` resource change was needed.
- **cad-io** — EPS import is a minimal path interpreter (no PostScript programming); PDF-based
  `.ai` files are rejected with a "save as SVG" message.
- **cam-2d** — Generators build `[CutPoint]` (material XY + depth) and emit through
  `Ops2D/Support/ToolpathBuilder`, the only place that turns them into `Move`s (via
  `MachineCoordinates`); it retracts to safe Z before every XY rapid and ends at safe Z.
- **cam-2d** — Arcs: toolpaths are computed as polylines (Clipper round-join offsets at the
  document tolerance), then `ArcFitter` re-fits G2/G3 arcs (≤180°, ≥3 chords, within 2× tolerance)
  on constant-depth runs. Ramps and tabs stay linear. `ProfileParameters.preferArcs = false` turns
  fitting off for profiles.
- **cam-2d** — Profiles use the even-odd region of ALL selected closed vectors, so nested vectors
  become islands: "outside" on a frame cuts outside the outer edge and inside the hole. Open
  vectors are always cut on the line, alternating direction each pass with no retract.
- **cam-2d** — Climb (clockwise spindle) keeps the finished part on the right of travel. So outside
  profiles run CW, while inside profiles and pocket walls run CCW and pocket islands run CW. Closed
  vectors cut "on" behave like outside.
- **cam-2d** — Tabs:
  - The raised length along the toolpath is tab length + tool diameter, so the bridge left in the
    part equals the tab length.
  - Added an additive `TabSettings.spacing: Double?`. When set, it overrides the count.
  - Triangular tabs peak at the tab top in the middle.
- **cam-2d** — Ramps:
  - Smooth: linear descent over max(length, Δ/tan(maxAngle)), then the ramp section is re-cut.
  - Zigzag: an even number of back-and-forth legs within `length`.
  - Spiral: one helical lap per pass plus a final flat lap.
  - Open chains always use zigzag. When a lead-in is enabled the ramp is skipped, because the
    plunge happens in the waste at the lead start.
- **cam-2d** — Plunges rapid down to a gap (0.05"/1 mm, never more than safe Z) above material
  known to be cleared (the top, or the previous pass depth), then feed at the plunge rate.
- **cam-2d** — Pocket offset clearing:
  - Each component is cut inside-out. A ring waits only for the deeper rings adjacent to it.
  - Rings and raster lines are linked at depth when a straight move, or a walk along the
    tool-centre boundary, stays inside the tool-centre region and is ≤ 2× the tool diameter.
    Otherwise the tool retracts.
  - Stepover is clamped to 95% of the diameter.
- **cam-2d** — Clearance tool:
  - The larger tool clears the whole pocket.
  - The primary tool then cuts the wall contour, plus offset-ring fragments near the rest material
    (the pocket minus the big tool's morphological opening).
  - The clearance tool is ignored unless it is larger than the primary tool.
- **cam-2d** — Drilling:
  - One hole per closed path, or per point-like path, de-duplicated. Arc-only paths use their
    exact centre; others use the bounds centre.
  - Pecks are explicit G0/G1 moves. Between pecks the tool retracts to `retractHeight` (capped at
    safe Z), then rapids back to 0.02"/0.5 mm above the previous peck.
- **cam-2d** — `ToolpathStats` (Ops2D/Support) computes cut and rapid length and an estimated time:
  Σ length/feed + rapids/rapidRate + dwells + an allowance per tool change. The preview's
  `MachiningTimeEstimator` can delegate to it.
- **cam-2d** — Fluting and Texture are implemented too (same folder):
  - Fluting ramps over `rampFraction` of the length (cosine when smooth). Symmetric flutes
    alternate direction.
  - Texture uses a seeded SplitMix64 to place sine-shaped dips along lines at `angle`, retracting
    between strokes.
- **cam-vcarve** — Selected closed vectors are merged with the even-odd rule (Clipper union,
  snapped to the Voronoi grid: 1e-4 in / 1e-3 mm), so nested contours are holes (text
  counters). Open vectors are ignored with a toolpath warning.
- **cam-vcarve** — Depth = startDepth + min(max(0, r − tipRadius) / tan(angle/2), limit), where
  limit = min(flatDepth, bit's full cutting depth). `flatDepth` is measured below `startDepth`.
  When the bit itself limits depth (no flat depth set), the toolpath carries a warning and the
  flat area is cleared like a flat-depth carve.
- **cam-vcarve** — Flat area = region inset by tipRadius + limit·tan(angle/2). With a clearance
  tool it is pocketed (offset or raster, stepped by the clearance tool's stepdown) and the V-bit
  traces the flat area's boundary at the flat depth plus the clamped medial axis (corner
  cleanup). Without one the V-bit clears it with offset/raster passes at its own stepover.
  Toolpath order: clearance tool first, then V-bit.
- **cam-vcarve** — `VCarveParameters.passDepth == nil` means a single pass (per the model doc);
  with a value, pass k only re-cuts where the target depth exceeds level k−1.
- **cam-vcarve** — Plunges go from safe Z at the plunge rate; medial-axis chains are walked
  through junctions to minimise lifts, gaps ≤ 0.002 in (0.05 mm) are linked at depth.
- **cam-vcarve** — Inlay: female = V-carve flat at `pocketDepth` P. Male = V-carve of
  (mirrored vectors' bounds grown by `maleBoundaryMargin`) minus the mirrored vectors, start
  depth S, total depth P (male flat depth below start = P − S). Walls coincide when the plug top
  sits S below the female surface, so the bottom gap is P − S; `glueGap` is enforced as the
  minimum bottom gap (S + glueGap ≤ P, else invalidParameter). Gaps are reported in toolpath
  metadata (`bottomGap`, `boardGap`). The male is generated in place (mirrored about its own
  bounds centre) — cut it on a separate board; `part: .both` emits female then male toolpaths.
- **cam-3d** — STL files have no units; `STLImporter` assumes millimetres (`sourceUnits`, default
  `.millimeter`) and converts to the document units. Vertices are merged on a 1e-7 grid and
  degenerate triangles dropped. A file whose size matches the binary layout is binary even if
  its header starts with "solid".
- **cam-3d** — `PlacedModel` mapping: material XY = mesh XY × `scale` + `offset`; mesh Z is
  stretched so its top sits `zTop` and its bottom `depth` below the material top. Outside the
  model's triangles the relief surface is that bottom plane. `ModelPlacement.place` fits/centres
  a mesh on the job.
- **cam-3d** — The relief heightmap is *conservative*: each cell stores the shallowest mesh point
  anywhere in its square (triangle clipped to the cell), and the drop-cutter honours each cell
  at its point nearest the tool axis. Finishing therefore never gouges the mesh at any
  resolution; the cost is up to ~slope × cell size of extra stock, so finer resolution = closer
  finish. Grids are capped (30M cells) and auto-coarsened with a toolpath `warning`.
- **cam-3d** — Roughing = z-levels (`passDepth` ?? tool stepdown, evenly spaced) raster-cleared
  where a flat cutter of radius R+allowance, raised by allowance, clears the model (allowance
  left both sideways and vertically). Levels are nested, so rapid descents stop 0.04 in / 1 mm
  above the previous level. `PocketStrategy.offset` is cut as raster (angle 0) for now and
  `profilePass` is ignored; noted in toolpath metadata. Roughing requires an end mill.
- **cam-3d** — Relief tool centre stays inside the boundary vectors (or the model footprint);
  output order is roughing then finishing, one toolpath each.
- **cam-3d** — Fluting/Texture generators live in `Ops3D/FluteToolpathGenerator.swift` and
  `Ops3D/TextureToolpathGenerator.swift` (public) because `Ops2D/` is owned by cam-2d. If cam-2d
  has not implemented `FlutingOperation`/`TextureOperation`, the integrator can forward their
  `generate` to these. Flute passes alternate direction (no retract between passes); texture
  strokes are half-sine scoops from a SplitMix64 PRNG seeded by `seed`, linked by feeding
  0.04 in / 1 mm above the top when close, region = selected closed vectors or the material.
- **preview** — Simulation sweeps each flattened motion segment analytically: every cell near
  the segment is cut by the tool profile (flat/ball/V) centred at the closest XY point of the
  segment. Segments are split so each piece descends ≤ one cell, which keeps ramps and helices
  accurate. Cuts are clamped to the material thickness, so spoilboard cuts are not shown.
- **preview** — Drill tools with an `angle` are simulated as a V point; without one, they are
  simulated as flat. Engraving tools are simulated as a V with a flat tip.
- **preview** — `MachiningTimeEstimator.estimate` gained a defaulted `toolChangeSeconds`
  parameter (default 90 s per manual change). Arcs are timed by their true helical length.
  There is no acceleration model.
- **preview** — The 3D preview uses SceneKit. The heightfield becomes a vertex-coloured mesh,
  decimated to ≤ 200k vertices. The cell size is automatic (~800k cells, min 0.004 in /
  0.1 mm). Scrubbing backwards restores the nearest checkpoint (every ~1/12 of the steps)
  and replays from there. The preview opens on the finished result.
- **preview** — App shell integration point: `ToolpathPreviewPanel(document:toolpaths:postProfile:)`
  provides the 2D/3D tabs. The canvas overlay uses
  `ToolpathOverlayRenderer.draw(ToolpathOverlay(toolpaths:coords:), in:transform:)`.
  `PreviewSamples.demo()` provides demo toolpaths.
- **app-shell** — Added test target `KerfAppTests` (depends on the `KerfApp` executable via
  `@testable import`) in Package.swift — additive only. App view-model logic lives in
  `Sources/KerfApp/Model/` as pure Swift so it can be tested without UI.
- **app-shell** — Documents use SwiftUI `DocumentGroup` + `ReferenceFileDocument` (`KerfDocument`).
  Undo is snapshot-based: every edit goes through `KerfDocument.perform`, which registers the
  previous `KerfProject` with the window's undo manager (also drives the dirty flag). The UTI
  `com.seanperkins.kerf.project` is declared in Info.plist by `scripts/bundle.sh`.
- **app-shell** — Toolpath results are kept in memory only (not saved) and marked stale when the
  operation, the design or the tool library changes; export recalculates stale toolpaths
  synchronously first so the G-code always matches the parameters.
- **app-shell** — Toolpath parameter edits happen on a draft in the inspector and commit on
  Save/Calculate (one undo step per commit, not per keystroke).
- **app-shell** — Combined G-code export groups toolpaths by tool by default (toggle in the export
  sheet). The validator runs on both toolpaths and generated text; errors require "Save Anyway".
- **app-shell** — Changing document units in Job Setup converts geometry, job, grid and all
  operation lengths (angles/percentages untouched). New operations get inch defaults ×25.4 in mm
  documents; profile cut depth defaults to the material thickness.
- **app-shell** — User post profiles are loaded from `~/Library/Application Support/Kerf/posts/*.json`
  (same id overrides a built-in). Default post follows document units (Avid inch/mm).
- **app-shell** — The canvas draws a basic 2D toolpath overlay (cuts solid per-operation colour,
  rapids dashed red). The 3D tab is a placeholder (`Preview3DHost`, TODO(integration)) for the
  preview workstream's view. Marquee: left→right = window (fully inside), right→left = crossing.

## integration

- **integration** — Merged the seven workstream branches into main in order post, cad-io, cam-2d, cam-vcarve, cam-3d, preview, app-shell. The only conflicts were appended sections in this file (all kept).
- **integration** — cam-2d and cam-3d both declared an internal `SplitMix64`; the cam-3d one is renamed `ReliefSplitMix64`. `FlutingOperation`/`TextureOperation` use the cam-2d implementations; the cam-3d `FluteToolpathGenerator`/`TextureToolpathGenerator` stay as public builders.
- **integration** — `KerfProject.decode` now goes through `KerfFile.decode`, so .kerf migrations run and files from a newer version are rejected.
- **integration** — The 3D tab (`Preview3DHost`) shows `SimulationPreviewView` for all enabled, calculated toolpaths using the selected post's rapid rate. The 2D toolpath overlay remains the design canvas's own drawing, so it shares the canvas zoom/pan.
- **integration** — G-code export no longer passes a material description to the post; the header already prints W x H x T, and the description line duplicated it.
- **integration** — End-to-end test (Tests/KerfAppTests/EndToEndSignTests.swift) runs the app model pipeline headlessly on Tests/Fixtures/e2e/sign.svg and compares against Tests/Fixtures/golden/sign-{materialTop,spoilboard}.tap. Regenerate with `KERF_UPDATE_GOLDEN=1 scripts/test.sh --filter EndToEnd`. The fixture text uses Helvetica-Bold outlines baked into the SVG, so font changes on the OS don't affect the test.
- **integration** — Drill pecks rapid back down to just above the previous peck depth (standard peck behaviour); the validator reports this as a "rapid plunge below material top" warning, not an error. Left as is.
- **integration** — samples/sign.svg is a copy of the e2e fixture for manual testing in the app.

## drawing

- **drawing** — Pure editing model lives in `CADCore/Editing` (PathNodes, ShapeNodes, TransformHandles,
  SnapEngine, PenPath, Grouping) and is unit-tested; the canvas only maps gestures onto it.
- **drawing** — Node editing works on an "editable form" of each path: arcs become cubic Béziers and
  closed paths get an explicit closing segment, so node indices are stable. The first node edit
  therefore converts that shape's arcs to cubics and drops parametric provenance (rectangle,
  circle…) — the shape becomes a plain drawn vector.
- **drawing** — Deleting a node between two curves keeps the outer handles (approximate merge);
  otherwise the neighbours are joined with a line. Paths never drop below 2 nodes (open) / 3 (closed).
- **drawing** — Groups are a `groupID` on `Shape` (optional, so older .kerf files still decode; no
  format-version bump). Clicking any member selects the group; grouping a member absorbs its whole
  group (flat groups, no nesting). The old merge-into-one-shape action is now "Combine", and
  "Break Apart" splits multi-path shapes.
- **drawing** — Snapping: object points (nodes, segment midpoints, bounding-box centres) within
  8 screen points win over the grid; Command temporarily disables snapping. Moves snap a corner,
  centre or node of the selection onto targets. Snap-to-grid moved to ⌘' (⇧⌘G is now Ungroup).
- **drawing** — Transform handles: corner/edge handles scale about the opposite handle (Shift keeps
  proportions, Option scales about the centre); the round handle above the box rotates (Shift
  snaps to 15°). Mirroring stays on menu/inspector buttons.
- **drawing** — Bézier pen is a separate tool (P); the old click-through smooth curve remains as
  "Smooth Curve". Canvas single-key tool shortcuts: V N R C E L P T.

## advanced-ui

- **advanced-ui** — Manual profile tabs are `TabSettings.manualTabs: [TabAnchor]?` (optional, so older .kerf files decode unchanged). An anchor is (shape id, path index, fraction of the flattened path length), so tabs follow the vector when it moves, scales or rotates. When manual, each anchor goes to the toolpath loop nearest its position; loops with no anchor get no tabs; overlapping tabs on a loop are merged (first one kept). nil = the existing automatic layout.
- **advanced-ui** — Tab editor: "Edit on Canvas" in the Profile inspector (Tabs → Placement: Manual). Click one of the toolpath's vectors to add a tab, drag a tab to slide it along the vectors, option-click to delete, Esc/Done to finish. Each edit is one undo step. Switching to Manual seeds evenly spaced anchors (tabs-per-vector on each closed path).
- **advanced-ui** — New Toolpath → Inlay opens a wizard that creates TWO InlayOperations (part = female "Pocket", part = male "Plug") sharing one set of settings, so each board's program can be saved separately. The single-operation `.both` part is still supported in the inspector.
- **advanced-ui** — Importing an STL no longer places the model silently: it opens "Place 3D Model" (size with locked aspect, centre/lower-left/custom position, model Z height, Z offset below the top) and by default creates two Relief3D toolpaths: "<name> Roughing" (end mill, finishing off) and "<name> Finishing" (ball nose, roughing off). Models can be re-placed later from the model's context menu. Multiple STLs queue their dialogs; import warnings are shown after the last one. `ImportService.importFile` still places STLs directly for headless use.
- **advanced-ui** — "Save All Toolpaths" offers: one file grouped by tool (default), one file in list order, one file per toolpath, one file per tool. Multi-file modes ask for a folder; clashing names get `_2`, `_3` suffixes. Every file is validated; saving with errors asks for confirmation.
- **advanced-ui** — "Check Toolpaths…" (⇧⌘K) validates each enabled toolpath on its own plus the combined program, showing only combined-program issues not already listed per toolpath. Uncalculated and failed toolpaths are listed as warnings.
- **advanced-ui** — The Toolpaths sidebar shows each toolpath's tools and estimated time, plus a footer with total time and the tool load/change sequence (grouped by tool or list order). The total sums per-toolpath estimates (no tool-change allowance).
- **advanced-ui** — Pocket's primary tool is labelled "Finish tool"; the clearance tool is only used when it is larger than the finish tool, and the form says so. Drill has a "Peck drilling" toggle (off = peck depth 0, single plunge) and a per-hole peck summary. `DrillOperation.peckDepths` is now public for that summary.
- **advanced-ui** — Tab spacing is now scaled with the other tab lengths when converting a document between inch and mm.

## review-fixes (ordering, inlay, open vectors, relief, booleans, async calc)

- **review-fixes** — "Group by tool" is now OFF by default and is one shared setting (`kerf.groupByTool` in UserDefaults) read by Export G-code, Check Toolpaths, the tool-change summary and the 3D preview, so the simulated order always matches the exported order. Save All defaults to "One file, in toolpath order". When grouping is on, `ToolpathOrdering.groupedByTool` only pulls a toolpath forward into an earlier same-tool group if it is not a profile, does not jump an earlier pass of its own operation, and its XY footprint (padded by both tool radii) does not overlap any toolpath it jumps. Otherwise the user's order wins.
- **review-fixes** — The inlay wizard creates the plug (male) operation disabled; the validator reports an error when inlay female and male toolpaths are in one program (the plug is generated in place over the pocket).
- **review-fixes** — SVG import closes subpaths whose ends meet within 0.0005 in / 0.01 mm (same as the DXF join tolerance; DXF already closed such loops through `joinOpenPaths`). Profile adds a metadata warning when Outside/Inside is selected but open vectors were cut on the line.
- **review-fixes** — New 3D Relief toolpaths rough with the first end mill in the library when the primary tool is not an end mill (roughing is turned off if the library has none). The roughing tool picker only lists end mills.
- **review-fixes** — Each `[Path]` argument to PathOps union(a,b)/subtract/intersect/xor/offset is one shape read even-odd (the CAM rule), normalised with an even-odd union first, so same-direction holes survive. Weld uses `union(shapes:)` (each shape normalised separately, then non-zero union); Subtract unions the cutters first. The single-list `union(_:)` keeps "every path is its own region" semantics.
- **review-fixes** — Export / Save All / Check sheets recalculate stale toolpaths in the background (`KerfDocument.calculateAndWait`) with a progress row and Stop button, and post only once results arrive. Every calculation gets a monotonic generation stamp; a result is stored only if newer than the stored one. A Calculate request for an operation that is already calculating is queued and runs once the current one finishes.

- **review-fixes** — **Profile leads are validated against the waste side.** The configured lead is tried first, then straight approaches (diagonal back, diagonal forward, pure normal) at shrinking lengths; the first that keeps every point in the tool-centre waste region wins, otherwise no lead. Fixes inside profiles starting at a sharp corner backing through the wall.
- **review-fixes** — **Pocket reports unreachable regions** as `metadata["warning"] = "N region(s) too small for the tool"` (computed with the finish tool, so it also covers rest clearing).
- **review-fixes** — **"One file per tool" follows the grouped-export safety rules.** Files are the runs of `ToolpathOrdering.toolGroups` (profiles never move, overlapping toolpaths keep their order), so a tool may get several files; names carry a run-order prefix (`01_`, `02_`, …).
- **review-fixes** — **The toolpath editor writes through.** Every form change is committed immediately (`updateOperationLive`), merged into one "Edit Toolpath" undo step until another change, undo or save. The Save button is gone; Revert restores the operation as it was when selected.

## packaging

- **packaging** — `samples/` is generated by `Tests/KerfAppTests/SampleFilesTests.swift`. A normal test run only checks that every sample imports, calculates and posts with no validator errors. `KERF_WRITE_SAMPLES=1 scripts/test.sh --filter SampleFiles` rewrites the files. The sign is 24 x 12 x 0.75 in, Material-top Z zero, lower-left origin and the Avid inch post. Toolpaths run in list order (Pocket, V-Carve, Drilling, Profile, so the part is cut free last). It has five drill holes: one hanging hole and four mounting holes.
- **packaging** — `relief.stl` is an ASCII STL in mm (75 x 75 mm, 1–6 mm tall, closed solid). `bracket-plate.dxf` is an 8 x 5 in plate with 4 bolt holes, a slot and a bore. Both go through the same importers the app uses.
- **packaging** — There is no app icon yet. `bundle.sh` copies `Resources/AppIcon.icns` if it exists.
- **packaging** — TESTING.md tells users to air-cut with Z zeroed 1–2 in above the material and the spindle off before any real cut.

## parity

- **parity** — `docs/PARITY.md` lists VCarve Pro 12.5 features, taken only from public Vectric pages, with Kerf's status for each. A feature is "done" only when it works end to end, UI included. Rotary, drill banks and tiling are P3 because the Avid PRO6096 has no rotary axis, has a single spindle and has a 60x96 in bed.

## vcarve-parity (round 1)

- **vcarve-parity** — Multiple flat-area clearance tools: `flatClearanceToolID` stays the first
  tool and `extraClearanceTools: [VCarveClearanceTool]` (V-carve and inlay) adds more, run in
  list order like Vectric's clearance tool list (the UI says to list them largest first; the
  order is not re-sorted). Tool k only cuts where the flat area minus everything earlier tools
  swept (their centre region grown by their floor radius) is non-empty: its centre region is
  (flat area inset by its wall clearance) ∩ (rest grown by its floor radius), cleared with
  rings/raster at its own stepdown. A later tool with nothing left is dropped with a warning.
  Tapered engraving tools may be clearance tools: their wall clearance is tip radius + flat
  depth · max(0, tan(tool half-angle) − tan(V half-angle)), capped at the tool radius.
  New parameter fields are decoded with `decodeIfPresent`, so older `.kerf` files open unchanged.
- **vcarve-parity** — Corner sharpening is a per-tool flag on the extra clearance tools
  (`VCarveClearanceTool.cornerSharpen`, shown only for tools with an angle), as in Vectric where it
  applies to second-or-later engraving tools. After its flat-depth clearing, the tool follows the
  region's medial axis wherever it lies in the flat area but outside everything already swept,
  at depth start + min(flat, (R − tip radius) / max(tan tool half-angle, tan V half-angle)), so the
  cone never cuts the V walls. The V-bit still traces the flat boundary and full medial axis
  afterwards, as before.
- **vcarve-parity** — Inlay plug boundary: `InlayParameters.plugBoundary` = `.boundaryOffset`
  (the old behaviour: bounds grown by `maleBoundaryMargin`), `.vectorOffset` (outer loops of the
  mirrored vectors grown by the margin, so counters are still cleared) or `.sheetLimits` (the
  whole material rectangle; slow without a clearance tool on a big sheet, like any huge flat
  area). `surfaceClearance` (nil = P − S, the old value) is the plug carve's depth below its
  start depth, i.e. how far the plug board's cleared floor sits above the pocket board when
  seated; it is reported as `boardGap`, must be > 0 and, when set, less than the material
  thickness. The bottom (glue) gap stays P − S.
- **vcarve-parity** — V-bit engraving of open vectors lives in the V-Carve toolpath:
  `VCarveParameters.openVectorDepth` (nil = ignore open vectors with a warning, as before) engraves
  each selected open vector along the line at start depth + depth; `openVectorTaper` (0…0.5) eases
  each end from the surface over that share of the length with a cosine profile (sketch-style
  strokes that start and end as points). The strokes join the V-bit's carve strokes, so pass
  depth, ordering and the move writer apply. A selection of only open vectors is valid when
  engraving is on. Closed vectors are still V-carved, never engraved along their outline.
- **vcarve-parity** — V-Carve `useSelectionOrder` / `useVectorStartPoints` (Vectric's "Use
  Vector Selection Order" / "Use Vector Start Points"). Strokes are assigned to the first selected
  shape (selection order = `setup.shapeIDs`, which the app fills in click order) that contains
  their middle point, or whose open path they lie on. Selection order cuts each shape's strokes
  together, per pass, shapes in order; strokes in no shape go last. Start points rotate closed
  loops (flat-area outlines, clearance rings) to begin at the vertex nearest the shape's first
  path start, start each shape's walk there, and keep engraved open vectors in their drawn
  direction. Medial-axis chains are not re-split at start points. Inlay does not offer these
  options (its plug geometry is mirrored).
- **vcarve-parity** — PhotoVCarve is a new operation kind `.photoVCarve` (`PhotoVCarveOperation`,
  additive enum cases in `OperationKind`/`AnyOperation` and their app switches). The picture is
  loaded with ImageIO, downsampled to ≤ 800 px on the long side, converted to 8-bit grey and
  stored in the operation (`GrayImage`, base64 in the `.kerf` JSON) so the file is
  self-contained. Grooves are parallel lines at `angle`, `lineSpacing` apart, across a
  placement rectangle (origin + width, height from the aspect); along each line the groove's
  top width = darkness × spacing, i.e. depth = max(0, w/2 − tip radius) / tan(half-angle), capped
  by the bit; samples shallower than `minDepth` lift the bit. Lines alternate direction. No
  bitmap is drawn on the canvas yet; the toolpath overlay shows the placement. New Photo
  V-Carve toolpaths start centred at 80% of the material.
## cam-3d parity round 1

- **cam-3d** — **3D roughing offset strategy and profile pass (3d-roughing).** Each Z level's tool-centre
  region is now contoured (marching squares) from a grid of flat-cutter drop depths computed for
  the whole heightmap at once (`ReliefHeightmap.eroded`, row-wise sliding minima). The cutter is
  grown by allowance + 1.5 cells so the contour is safe between grid points; saddle cells are
  always split; contours are simplified within tolerance/2 and shrunk by the same amount, then
  clipped to the boundary. The region is cleared with the 2D `PocketPlanner` (radius 0):
  `.offset` = contour-parallel inside-out rings, `.raster` = zig-zag lines plus the region contour
  when `profilePass` is on. Links stay inside the level's region (`RegionLinker`), other moves
  retract. This replaces the earlier per-raster-line sampling, so raster roughing toolpaths changed.
- **cam-3d** — **Composite models (3d-multiple-models).** `Relief3DParameters.additionalModelIDs`
  (optional, so older files decode) lists models machined together with `modelID`. They are
  rasterised into one heightmap where each cell keeps the shallowest point of any model (a union);
  cells no model covers sit at the deepest model's bottom plane. The default area is the union of
  the models' footprints. Missing combined models are skipped with a toolpath warning (a missing
  primary model is still an error). The inspector lists the other models under "Combine with".
- **cam-3d** — **Offset and spiral 3D finishing (3d-finish-offset).** `FinishingSettings.strategy`
  (optional; nil = raster). Offset = the boundary region's inward rings (`PocketPlanner.offsetLevels`,
  radius 0) cut outermost first, each started at the point nearest the tool and linked along the
  surface when the next ring is within 2.5 × stepover. Spiral = each run of levels with exactly one
  ring is blended into one path (going once round ring k while moving linearly onto ring k+1,
  matched by arc-length fraction), ending with a full lap of the innermost ring; where the area
  splits into several rings those levels are cut as offset rings. Every point is dropped with the
  drop-cutter, so no pattern can gouge the model; on very non-convex boundaries a blended spiral
  point may stray slightly outside the boundary between two rings.
- **cam-3d** — **3D rest machining (3d-rest-machining).** `FinishingSettings.restToolID` names the
  larger tool that already finished the surface ("Rest after" in the inspector). On the heightmap
  grid (drop-cutter rule: each cell square reached at its point nearest the tool axis) Kerf drops
  the larger tool at every cell, takes the upper envelope of its tip shape as the surface it left,
  then drops the finishing tool onto that surface and onto the model. Cells where the finishing
  tool sits deeper on the model by more than max(0.002 in / 0.05 mm, cell/2) form the rest mask
  (the cell term absorbs the conservative heightmap's slope noise). The mask is grown by
  max(stepover, tool radius / 2), contoured and clipped to the boundary, and the chosen finishing
  pattern runs only there. It assumes the larger tool covered the whole area including its reach.
  If nothing is left and the operation has no roughing toolpath, it fails with a clear message.
- **cam-3d** — **Projecting 2D toolpaths onto a model (3d-project-2d).** `OperationSetup.projectOntoModelID`
  (optional, additive) is honoured in `AnyOperation.generate` for every kind except 3D Relief, so
  calculation, export and Check Toolpaths all see the projected moves. `ReliefProjection` (Ops3D)
  linearises arcs, subdivides cutting moves to the heightmap cell (0.01 in / 0.25 mm, capped like
  relief), and sets each point's depth to the toolpath tool's drop-cutter depth on the model plus
  its original depth below the material top; points are thinned within the document tolerance.
  XY rapids are unchanged (safe Z); vertical rapids below the material top are clamped to the top
  so a pass never rapids into material that was cleared somewhere else before projection. Outside
  the model's triangles the surface is its bottom plane (same as 3D Relief). Inspector:
  "Project onto 3D" picker under the vectors row, shown when the document has models.
- **cam-3d** — **Two-sided 3D machining (3d-two-sided).** `Relief3DParameters.twoSided` (optional): side
  (top/bottom), flip (left-right = turned over about the vertical centre line, X mirrored;
  top-bottom = Y mirrored), split depth (nil = halfway between the model's top and bottom) and
  web. It is per toolpath: make one Relief3D toolpath per side. The bottom side is computed in the
  flipped board's frame: models are mirrored in XY and Z with depths measured from the old bottom
  face, boundary vectors are mirrored, and the result is ordinary top-down G-code for the flipped
  board (same XY origin and Z-zero rules). The top side's surface is clamped at the split depth;
  the bottom side stops `web` short of it (default 0.04 in / 1 mm), so the part stays attached by a
  thin web instead of being released. Registration relies on stock cut exactly to the job size and
  pushed against the same corner; there are no registration-pin toolpaths yet. This is independent
  of a job-level two-sided setup (`io-two-sided-setup`), which is owned by another area.
- **cam-3d** — **Rotary / wrapped toolpaths (3d-rotary): not implemented, by decision.** The Avid
  PRO6096 has no rotary axis, the Mach4 post has no A-axis output and nothing could be tested on the
  machine, so emitting wrapped A-axis G-code would be untestable and unsafe. Left as missing (P3).
## preview (parity round 1)

- **preview** — pv-time-accel: `MachineMotion` + `MotionPlanner` (CAMCore/Simulation) give the time estimate a trapezoidal velocity profile: one acceleration for all axes, junction-deviation cornering (0.002 in), full stops at dwells, tool changes and reversals, forward/backward speed passes over the whole job. `SimulationTimeline` lays steps out with these durations, so preview playback follows the same clock. A calibration `timeScale` multiplies motion and dwell time but not tool-change allowances. Default `.instant` keeps the old length / feed behaviour for every existing caller.
- **preview** — Time-estimate settings are per user (UserDefaults `kerf.time.*`), not per post profile: acceleration (stored in in/s², default 15 in/s², a conservative guess for a stepper gantry — not a published Avid number), scale factor (clamped 0.2–5), tool-change allowance (90 s). Edited from the stopwatch popover in the 3D preview, which can also calibrate the scale from a measured run time of the previewed job. `ToolpathCalculator`, the operation editor and Save All use them; changing them refreshes stored per-operation estimates.
- **preview** — The G-code header estimate (`PostTimeEstimator`, owned by post) is unchanged so golden files stay stable; it remains length / feed + spindle dwell. TODO(post): accept a `MachineMotion` if the header should match the app.
- **preview** — pv-preview-selected: the 3D preview has a scope picker (UserDefaults `kerf.previewScope`): All Toolpaths (enabled + calculated, the export set), Visible Toolpaths (also skips toolpaths whose eye is off in the list), Selected Toolpath (the list selection, simulated even when disabled). Every scope starts from fresh stock; there is no accumulate-on-top mode. Order follows the shared "group by tool" setting.
- **preview** — pv-material-texture: stock colouring is `StockAppearance` (CAMCore, pure): eight material presets (pine, maple, oak, cherry, walnut, MDF, HDPE, aluminium) with surface / machined-shallow / machined-deep / side colours, a procedural long-grain pattern along X (wavy rings, thin dark latewood lines; rings shift with depth so carved areas show different grain) and a specular strength. Options: painted top (uncut cells only, so carving shows bare material) and one flat colour for all machined areas. Colours are per-vertex (no image textures), so grain detail is limited by the preview mesh resolution. Chosen from the palette popover in the 3D preview; stored per user (`kerf.preview.*`). Default is pine.
- **preview** — pv-measure: a ruler toggle in the 3D preview turns on click-to-measure. A click hit-tests the stock mesh (the cutter and markers are ignored), converts to the material frame and re-reads the depth from the simulated heightfield at that XY (the mesh is decimated). One pick shows X, Y (material frame, same as the 2D canvas), depth and material left; a second pick adds 3D distance, XY distance and depth change; a third starts over. Picks on a vertical wall report the floor/top depth at that XY. Markers are drawn over the stock; measurements clear when the simulation is rebuilt or measuring is turned off. Orbit/zoom still work while measuring (drag vs click).
- **preview** — pv-save-image: the camera button in the 3D preview renders the scene offscreen with `SCNRenderer` (Metal) from the on-screen camera at 2x the view size (1600 x 1000 when the view size is unknown) and saves a PNG named "<document> preview.png". The cutter and measurement markers are included as shown; there is no menu item yet (keeps KerfCommands untouched).
- **preview** — pv-step-control: `SimulationMoveIndex` (CAMCore) groups timeline steps back into toolpath moves (an arc is one move; zero-time moves are skipped). Step forward jumps to the end of the move in progress, step back to its start (or the previous move's start); both pause. "Run to next retract" plays at the chosen speed and stops at the end of the next rapid that raises Z. The info badge shows "Move k / N · Feed|Plunge|Rapid|Retract". No keyboard shortcuts for stepping, to avoid stealing arrow keys from text fields.
## toolpaths-2d (parity round 1)

- **toolpaths-2d** — tp-profile-last-pass: `ProfileParameters.lastPass: ProfileLastPass?` (nil = off, so old files decode). When on (closed vectors cut outside/inside, allowance > tolerance), every roughing pass is offset by an extra `allowance`; after ALL roughing loops the tool cuts the true offset once more, inner loops first, in the opposite direction when `reverseDirection` is set. By default the last pass is one lap at the full cut depth (`fullDepth`), otherwise it repeats the normal depth passes. Tabs, ramps and leads apply to the last pass as well. The last pass plunges from the material-top gap (not a rapid into the roughed slot), because the allowance strip is still standing there. Ignored for "On" and for open vectors.
- **toolpaths-2d** — tp-pocket-multi-tool: `PocketParameters.clearanceToolIDs: [UUID]?` (nil = use the legacy single `clearanceToolID`; the editor writes the list and keeps `clearanceToolID` equal to its first entry so older readers still see one tool). Tools cut in list order. A tool is ignored (with a warning on the finish toolpath) unless it is smaller than the previous used clearance tool and larger than the finish tool. The first tool clears the whole pocket; each later clearance tool does rest machining against the previous tool's radius and cuts the walls only near rest material (`PocketPlanner.restClearing(fullWalls: false)`); the finish tool still finishes the whole wall. Toolpaths are named "<name> (clearance N)" when there are several.
- **toolpaths-2d** — New operation kinds `OperationKind.engrave` / `.chamfer` with `AnyOperation.engrave` / `.chamfer` (additive enum cases; every switch over them is in CAMCore or KerfApp and was updated). Parameters live in the new file `Model/Parameters/ParametersToolpaths2D.swift` and the forms in `Panels/Toolpaths2DForms.swift` to keep shared-file edits small.
- **toolpaths-2d** — tp-quick-engrave: "Quick Engrave" cuts every selected vector on its centreline at a fixed depth (DepthSettings, so multi-pass works). It is generated by an "On" profile with no tabs/ramps/leads and retagged `.engrave`, so ordering and direction rules match Profile. The V-bit width preview is the groove width (`EngraveOperation.cutWidth`: V cone, ball radius, or diameter) shown live in the form and as toolpath metadata; the 2D canvas overlay still draws the centreline (the 3D preview shows the real groove).
- **toolpaths-2d** — tp-chamfer: "Chamfer" needs a V-bit/engraving bit with an angle. Size by width (default) or by depth: depth = vDepth(2·(width + tipClearance)); the tip runs on the vector, or `tipClearance` into the waste (outside = waste outside the vector, inside = waste inside, on = on the line). Implemented as a profile whose offset equals the tip clearance (allowance = clearance − radius), retagged `.chamfer`. A chamfer wider than the bit's cone (tip radius + depth·tan(angle/2) > radius) is an error. Metadata and the form show width × wall height × tip depth.
- **toolpaths-2d** — tp-profile-open-sides: `ProfileParameters.openVectorSide: OpenVectorSide?` (on / left / right of the vector's drawn direction; nil = on, as before). It is independent of the closed-vector side. The offset path (tool radius + allowance) is traced from Clipper's butt-ended outline of the polyline (`OpenOffset.oneSided`): the walk between the two end-cap corners on the chosen side. If that cannot be traced (self-crossing vectors, folds tighter than the offset) the vector is cut on the line with a warning. Passes still alternate direction with no retract, like on-the-line open cuts.
- **toolpaths-2d** — tp-pass-editor: `DepthSettings` gained `customPasses: [Double]?` and `exactStep: Bool?` (both optional, nil = the old evenly divided passes). Custom passes are absolute depths below the top; they are sorted, de-duplicated, clamped to (start, cut) and the cut depth is always the last pass, so a bad list can never cut deeper than the cut depth. Exact step keeps every pass exactly the pass depth apart and puts the remainder in the last roughing pass. "Last pass thickness" is the existing `finalPassDepth`. The form's "Passes" picker (Even / Exact step / Custom) lives in `PassEditor` and lists the resulting pass depths; switching to Custom seeds the list from the current passes. Every operation that uses `DepthSettings` (Profile, Pocket, Fluting, Engrave) gets it.
- **toolpaths-2d** — tp-profile-start-point: `ProfileParameters.startPoint: ProfileStartPoint?` (nil = nearest, the old optimised behaviour). `vectorStart` rotates each closed loop to the point nearest the start node of the source vector closest to it, and stops open vectors being reversed. `left/right/bottom/top` start at the middle of that side of the loop's own bounding box. Loops are still visited in the same order; only their start point changes. Applies to the last pass too.
- **toolpaths-2d** — tp-profile-order: `ProfileParameters.order: ProfileOrder?` (nil = nearest neighbour, as before; also: selection order, left→right, bottom→top, grid). Each loop is ranked by its outermost containing loop ("part"), so a part's holes are cut right before the part; inner-before-outer precedence is never broken. Left→right/bottom→top use the part's bounding-box min X / min Y; grid bands parts into rows from the bottom (row height = median part height) and goes left→right in each row (not serpentine). Selection order matches each loop to the nearest selected vector (setup.shapeIDs order). Loops still start at the point nearest the previous position unless a start point is chosen.
- **toolpaths-2d** — tp-sharp-corners: `ProfileParameters.sharpCorners: Bool?` switches the profile offset from round joins to Clipper miter joins (limit 4× the offset; sharper corners are squared off at that distance). The part's external corners stay sharp either way; the option makes the tool run out to the square corner instead of rolling round it (square waste corners, no dwell on the corner). Applies to outside and inside cuts (island corners) and to the last pass.
- **toolpaths-2d** — tp-pocket-profile-pass: `PocketParameters.profilePassFirst: Bool?` (nil = after, as before). `PocketStrategy.raster(angle:profilePass:)` is unchanged so files and other users (V-Carve flat area, 3D roughing) are untouched; only the Pocket form shows Profile pass None / First / Last. "First" cuts the wall contour of each region before its raster lines at every depth pass.
- **toolpaths-2d** — tp-helical-hole: new `OperationKind.holeMill` ("Hole Milling") with `HoleMillParameters`. One hole per closed vector (arc-only paths: exact centre and radius; others: bounds centre and the smaller bounds side; concentric paths keep the largest), or a fixed diameter for all. Helical bore: helix at (hole − tool)/2 from the start depth down to the cut depth, at most the depth-per-turn (default the tool stepdown) per revolution, then one flat lap and a move back to the centre before retracting; climb = counter-clockwise. A hole the tool's size is a straight plunge; smaller holes are skipped with a warning. Thread mill (internal only): plunge at the centre (a pilot hole is required, the form says so), feed out, whole turns at the thread pitch — climb right-hand goes up counter-clockwise from the cut depth, conventional goes down clockwise ending at the cut depth, left-hand mirrors the rotation. Helices are emitted as line segments within the chordal tolerance (no helical G2/G3), so every post handles them.
- **toolpaths-2d** — tp-prism: new `OperationKind.prism` ("Prism Carve", V-bit only). The surface a V-bit leaves when its tip follows an outline at depth D is −D + distance/tan(half angle), so each connected shape (outer loop + its holes) is cut by running the tip along its outline at D = vDepth(2 × largest inscribed radius): the flanks meet at the material top at the widest point and form a ridge along the centreline (narrower parts get a lower ridge). The inscribed radius comes from a binary search on inward Clipper offsets. D is capped by the bit (cone wider than the tool: flat top + warning) and by the optional max depth. The outside of the outline is a matching V bevel; no separate clearing. Multi-pass at the pass depth, continuous round each loop.
- **toolpaths-2d** — tp-templates: `CAMCore/Templates/ToolpathTemplate.swift` (new folder). A template (`.kerftoolpaths`, pretty JSON, `formatVersion` 1) stores every toolpath with its vector references stripped (shape IDs, manual tabs, relief boundary), the units its lengths are in, a copy of each tool used, and a `VectorSelector` per toolpath = the most common layer name of its original vectors (matched case-insensitively) + closed / open / any. Applying (Toolpaths → Apply Toolpath Template…) adds every toolpath with a fresh id, converts lengths to the document's units, picks all vectors on that layer of that kind, renames on clashes ("Name 2"), and adds template tools the project and library do not have to the project's tool snapshot. Toolpaths with no matching vectors are still added (reported, so the user can select vectors); 3D reliefs take the design's first model or are skipped. Save is Toolpaths → Save Toolpath Template… (all toolpaths).
- **toolpaths-2d** — tp-tool-groups-materials: `Tool.group: String?` ("/"-separated folder; nil = listed under its type, as before) and `Tool.materials: [MaterialCuttingData]?` (RPM, feed, plunge, pass depth, stepover per material name, in the tool's units; `converted(to:)` scales them). `JobSetup.material: String?` names the job's material (Job Setup → Material type, with a menu of the names tools know). `CAMContext.tool(_:)` applies the matching material entry (case-insensitive) before unit conversion, so every operation picks it up; tools without an entry keep their defaults. The tool list shows named groups (alphabetical, "A › B") before the type sections. All new fields are optional, so old tools.json and .kerf files decode unchanged.
- **toolpaths-2d** — tp-feeds-calculator: `CAMCore/Tools/FeedsAndSpeeds` (feed = RPM × flutes × chip load, the inverse forms, and surface speed in SFM or m/min). The tool editor shows the current chip load and surface speed and has a target chip load field with "Apply" to set the feed rate. No built-in chip-load tables (they depend on the bit maker); the user enters the value from their chart.
- **toolpaths-2d** — tp-tool-edit-per-toolpath: `OperationSetup.toolOverride: ToolOverride?` (optional RPM, feed, plunge, pass depth, stepover in document units). `AnyOperation.generate` puts it in `CAMContext.toolOverrides` for the primary tool only, so the generators, the toolpath's tool copy, the post header and time estimates all see the changed values and the tool database is untouched. The inspector shows it as "Tool overrides" under the tool picker. Unit conversion of a project scales the override.
- **toolpaths-2d** — tp-keepout: `Document.keepOutZones: [KeepOutZone]?` (outline polygon in the material frame + height of the obstacle's top above the material top). Zones are made from selected closed vectors in Toolpaths → Keep-Out Zones… (default height 1 in / 25 mm; name and height editable; undoable) and drawn hatched red on the canvas. They are a safety check, not an avoidance planner: `KeepOut.violations` samples every move (rapids and arcs included) and reports a toolpath that comes within tool radius + 0.05 in (1 mm) of a zone while lower than its top + the same margin. `GCodeExporter.export` adds these as errors, so Export, Save All and Check Toolpaths all show them (Save All asks before writing files with errors). Toolpaths are not re-routed round zones; the user moves the clamp or the vectors, or raises safe Z.
- **toolpaths-2d** — tp-array-copy: `OperationSetup.arrayCopy: ArrayCopySettings?` (columns × rows at X/Y spacing, any operation). `AnyOperation.generate` repeats each generated toolpath's moves shifted by every grid offset (arc centres too) in one toolpath, rows in serpentine order; each copy already starts and ends at safe Z, so the joins are safe-Z rapids. Vectors are not copied. Copies whose cuts leave the material add a toolpath warning (the validator only checks machine travel, not material bounds). Shown in every toolpath's inspector under "Array Copies"; spacing scales with unit conversion.
- **toolpaths-2d** — tp-merge: new `OperationKind.merge` / `MergeOperation` holding copies of the merged operations (`MergeParameters.children`), so a merge is self-contained in the .kerf file. Toolpaths → "Merge With Next Toolpath" only merges a toolpath with the one directly after it when both have the same primary tool (no reordering, so no new safety risk); repeating it grows the merge, "Split Merged Toolpath" (or the inspector button) puts the parts back. Generation runs each child (with its own overrides/arrays) and joins consecutive results with the same tool and RPM into one toolpath; a clearance tool inside a pocket stays its own toolpath. A merged toolpath containing a profile keeps `kind = .profile` so group-by-tool export never moves it earlier. 3D reliefs are not mergeable. Templates store a merge as its separate parts.
- **toolpaths-2d** — tp-inlay-straight: new `OperationKind.straightInlay` (end mill). Both parts are cut from one matched outline M = close(open(S, r), r) (Clipper offsets by ∓r/±r), so the pocket's rounded inside corners and the plug's rounded concave corners agree. The pocket is an offset pocket of M to the pocket depth; the plug is an outside profile of M shrunk by `clearance` to the plug depth, optionally mirrored about M's bounding-box centre. Toolpaths are tagged `kind = .inlay` with `part` metadata so the existing validator error for pocket + plug in one program applies. New Toolpath → "Straight-Wall Inlay (Pocket + Plug)" adds a Pocket operation and a disabled Plug operation (as the V-carve inlay wizard does). No tabs on the plug (it is cut to the plug depth, not through).
- **toolpaths-2d** — tp-moulding: new `OperationKind.moulding`. The toolpath's vectors are rails; `MouldingParameters.sectionShapeID` is a separate cross-section vector (when created with 2+ vectors selected, the last selected is the section; the inspector can also set it). The section's bounding box maps X to the distance from the rail and Y to height (its top = material top); its upper envelope is sampled. Passes run along rail offsets (open rails: `OpenOffset` to the left/right; closed rails: inward) every stepover across the width; each pass depth is a 1D drop-cutter of the tool shape (ball, flat or V) against the section, flat beyond its ends, so the tool never cuts below the profile. Exact for straight rails; curved rails apply the section along the offset normals (no 3D surface/heightmap). Optional roughing cuts every pass limited to stepdown levels first. Templates drop the section reference (the user sets it again).
- **toolpaths-2d** — Not implemented this round (left clean, no UI): tp-drill-bank — the Avid PRO6096 has one spindle and Mach4 has no drill-bank head to drive, so there is nothing to output. tp-tiling — the 60 × 96 in bed takes full sheets; tiling needs every cut split at tile edges with fresh plunges and an indexing workflow, which is a safety-sensitive change with no use on this machine. Both stay "missing" in PARITY.md.
- **toolpaths-2d** — PARITY.md rows for the items above were updated (status + evidence); the totals line at the top was left for the integrator to recount after merging the parallel branches.
## app-ux

- **app-ux** — **Machines are separate from posts.** `MachineDefinition` (PostCore) holds the bed/Z travel (`MachineLimits`), spoilboard allowance, optional rapid rate, max feed and RPM range, and the list of compatible post ids. `KerfProject.machineID` is optional (older files decode; nil is not written). Resolution: the chosen machine, else the first machine whose posts include the job's post, else none (the post's own limits, as before). `KerfDocument.postProfile` is the post with the machine's limits converted into the post's units, so validation, export, time estimates and the preview all use the machine envelope. Built-ins: Avid PRO6096 (same limits as the Avid posts, so existing jobs validate identically) and Generic GRBL. User machines are JSON in `~/Library/Application Support/Kerf/machines/` (same id overrides a built-in). Picking a machine switches to its default post (matching document units) only when the current post does not drive it; both changes are one "Change Machine" undo step. Choosing a post is now "Change Post Processor". Job Setup warns when the material is larger than the bed or thicker than Z travel.
- **app-ux** — **Preferences** (Kerf ▸ Settings…, a SwiftUI `Settings` scene) are `AppPreferences`, stored as individual `kerf.pref.*` UserDefaults keys (invalid values fall back to defaults). They seed *new* documents only: units, grid spacing per unit, default machine and post (a default post that does not drive the default machine is ignored), and the snapping toggles of each new window. Canvas colours (material, selection, rapids) apply live. The Machines tab lists machines; built-ins are read-only and "Duplicate" makes an editable custom copy saved as JSON. `kerf.groupByTool` stays where it was (export sheet toggle).
- **app-ux** — **Autosave and crash recovery.** Saving still goes through `DocumentGroup` (system autosave/versions). On top of that, `RecoveryCoordinator` writes a recovery copy (`Recovery/<window id>.kerf` + `.json` metadata in Application Support/Kerf) of every open document whose project differs from the last opened/saved state (`KerfDocument.lastSavedProject`, updated in `snapshot`), every 60 s by default (Preferences: off/30 s/1/2/5 min). Copies are removed when the document becomes clean, its window closes, or Kerf quits normally (only this session's own copies). Copies left at the next launch mean Kerf did not quit normally: an alert offers Recover (opens each copy as a new untitled document via `NSDocumentController.duplicateDocument`), Not Now, or Discard. Recovered/discarded copies move to `Recovery/Archive` (newest 20 kept) instead of being deleted. File ▸ Recover Unsaved Work… re-offers them. The original file path is not recorded (`ReferenceFileDocument` does not expose it), so recovered work is always "Save As".
- **app-ux** — **Help** is built in, not an Apple Help Book (a help book needs an indexed bundle; the app is built with SwiftPM only). `HelpTopic` holds Kerf's own Markdown text per topic; Help ▸ Kerf Help (⌘?) opens a searchable Help window. Forms and inspector sections have a "?" (`HelpLink`) that opens their topic: every toolpath type, tabs/ramps, Job Setup, export, Save All, Check, Inlay wizard, 3D placement, tool database, node editing, arrange, preferences and machines. `NumberField`/`LengthField`/`OptionalLengthField` fall back to `FieldHelp` tooltips keyed by label when no explicit help is passed.
- **app-ux** — **Welcome window and samples.** Help and Welcome are AppKit `NSWindow`s hosting SwiftUI (`HostedWindows`), not SwiftUI `Window` scenes, so they can be opened from the app delegate at launch, from sheets and from menus without an `openWindow` environment. The Welcome window shows at launch (Preferences toggle, also on the window itself) and from Help ▸ Welcome to Kerf: New, Open, "Open the Sample Sign", Getting Started help, and six quick-start steps. `scripts/bundle.sh` copies `samples/` into `Kerf.app/Contents/Resources/samples`; unbundled runs fall back to the checkout's `samples/` (found via `#filePath`). The sample sign opens as an untitled copy (`duplicateDocument`) so the shipped file is never overwritten; DXF/STL samples are revealed in Finder for File ▸ Import.
- **app-ux** — **Accessibility.** The canvas `NSView` is a VoiceOver group ("Design canvas") whose value summarises the job and whose children are one element per visible vector (up to 400), labelled with kind, size, position, layer and state (`CanvasAccessibility`, pure and tested); pressing an element selects the vector. Tab / Shift-Tab on the canvas select the next / previous editable vector (one stop per group, wrapping) and announce it; Control-Tab still moves focus out of the canvas (standard AppKit convention for views that use Tab). Icon-only buttons (layer eye/lock/colour, toolpath visibility/status/calculate, check, delete, tool database, tool palette) have explicit accessibility labels. Contrast: canvas material, selection and rapid colours are adjustable in Preferences; SwiftUI controls follow the system Increase Contrast setting.
- **app-ux** — **Side-by-side view.** `CenterMode.split` ("2D | 3D" in the toolbar picker, View ▸ Show 2D and 3D Side by Side, ⌥⌘2) shows the design canvas and the 3D simulation in an `HSplitView`; both observe the same document, so edits and recalculations update both. Actions that need the canvas (tab editing, STL placement) call `showDesignCanvas()`, which keeps the split instead of forcing 2D.
