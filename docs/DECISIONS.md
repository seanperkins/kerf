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
