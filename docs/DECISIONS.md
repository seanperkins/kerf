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
