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
