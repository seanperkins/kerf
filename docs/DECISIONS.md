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
