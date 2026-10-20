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
