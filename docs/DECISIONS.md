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
