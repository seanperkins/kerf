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
