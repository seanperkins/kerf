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
