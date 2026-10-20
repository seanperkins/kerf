# Kerf — design spec (2026-10-19)

Kerf is a native macOS 14+ (Apple Silicon) 2D/2.5D + basic 3D CAD/CAM app that replaces
VCarve Pro for producing G-code for the Avid CNC PRO6096 (Mach4).

## Architecture

SwiftPM only (Command Line Tools, no Xcode). Modules, bottom-up:

| Target | Lang | Role |
|---|---|---|
| `Clipper2` | C++ | Vendored Clipper2 1.5.4 (`Vendor/Clipper2`), untouched. |
| `CGeom` | C++ → C API | `Sources/CGeom/include/CGeom.h`: offsets, booleans (closed + open subjects), Voronoi of points/segments with sampled edges carrying inscribed radius. Boost.Polygon Voronoi headers from `Vendor/Boost`. Only C types cross the boundary. |
| `CADCore` | Swift | Geometry primitives and the design document; Swift bridge `GeomKernel` over CGeom; import/export; tool database. |
| `CAMCore` | Swift | Moves, toolpaths, operations + generators, machine-coordinate mapping, simulation/time estimate, `.kerf` project. |
| `PostCore` | Swift | Data-driven post processor (`PostProfile` JSON), built-in profiles, G-code validator. |
| `KerfApp` | SwiftUI + AppKit | Executable `Kerf`; canvas, panels, preview. Wrapped into `dist/Kerf.app` by `scripts/bundle.sh`. |

Dependencies: `KerfApp → PostCore → CAMCore → CADCore → CGeom → Clipper2`.

## Data model

* **Frames.** Document geometry lives in the *material frame*: (0,0) = lower-left corner of
  the stock, X right, Y up, document units. Toolpath `Move`s are in *machine coordinates*.
  `CAMCore.MachineCoordinates` is the only conversion point:
  * XY: `machine = material − job.originInMaterialFrame` (4 corners or centre).
  * Z: generators reason in *depth below material top* (positive = into stock).
    `materialTop`: `z = −depth`; `spoilboard`: `z = thickness − depth`.
    Safe Z / home Z are heights above the material top, mapped the same way.
* **Path** = `start` + `[PathSegment]` (`line`, `arc(center, clockwise)`, `cubic`) + `isClosed`.
  Flattening uses a chordal tolerance. **Shape** = id, name, layerID, `[Path]`, `ShapeOrigin`
  (parametric provenance for re-editing). **Layer**, **Document** (name, units, `JobSetup`,
  layers, shapes, `PlacedModel`s with `Mesh3D`, grid spacing).
* **JobSetup**: width, height, thickness, `XYOrigin`, `ZZeroMode {materialTop, spoilboard}`,
  `safeZ`, `homeZ` (above top), `home` (machine XY).
* **Tool**: kind (end mill / ball nose / V-bit / engraving / drill), number, diameter, flutes,
  angle, tip diameter, stepdown, stepover (distance), RPM, feed, plunge, own units.
  `ToolLibrary` persists to `~/Library/Application Support/Kerf/tools.json` (seeded defaults).
* **Operations**: `ToolpathOperation` = `OperationSetup` (id, name, enabled, toolID, shapeIDs)
  + a parameter struct; `generate(in: CAMContext) -> [Toolpath]` (one toolpath per tool).
  `AnyOperation` is the Codable enum stored in `KerfProject`.
* **.kerf file**: pretty-printed JSON of `KerfProject {formatVersion, document, operations,
  tools snapshot, postProfileID}`.

## Toolpath algorithms

Common: passes from `DepthSettings.passDepths` (evenly divided, ≤ stepdown, optional finishing
pass). Every toolpath starts with a rapid at safe Z, retracts to safe Z before any XY rapid,
plunges at plunge rate, and ends at safe Z. Shortest-path ordering of loops (greedy nearest
neighbour), inner-before-outer for profiles.

* **Profile**: offset each closed vector by ±(r + allowance) with Clipper (round joins);
  `on` = no offset (open vectors allowed only for `on`). Climb vs conventional selects loop
  direction (outside+climb = CW for a clockwise-spinning spindle). Multi-pass Z levels; tabs
  are intervals along the final passes' arc length where Z is raised to `cutDepth −
  thickness` (rectangular or triangular). Ramps replace plunges (zig-zag along the path within
  `length`, limited by `maxAngle`; spiral = continuous descent around the loop). Lead-in/out:
  linear or tangent arc outside the part, plus overcut. Arcs from the source survive as
  G2/G3 when the offset is an exact arc (circle/rounded-rect offsets are re-fitted), else lines.
* **Pocket**: region = union of closed shapes (even-odd for holes) shrunk by r + allowance.
  Offset strategy: repeated inward offsets by stepover until empty, each nesting linked
  innermost→outermost; raster: parallel lines at angle clipped against the region with Clipper
  open-path booleans, zig-zag linked when the connector stays inside, + optional boundary pass.
  Clearance tool: clear with the large tool, then the primary tool machines only the rest
  region (region − large-tool-reachable area, via offset-in/offset-out).
* **Drill**: centre of each selected closed shape (circle centre / bounds centre) or point;
  peck cycle emitted as explicit moves (G0/G1, no canned cycles) for portability.
* **V-Carve**: build Voronoi of the shapes' flattened segments (CGeom), keep primary edges
  strictly inside the region; each sample point's depth = radius / tan(angle/2) (minus the tip
  radius offset for flat-tipped bits), clamped at `flatDepth`. Chain edges into polylines by
  shared vertices and cut them as 3D polylines. With a flat depth: the area where radius ≥
  flat-width is pocketed at `flatDepth` with the clearance tool and the V-bit traces its
  boundary. Optional multi-pass when depth exceeds `passDepth`.
* **Inlay**: female = V-carve with flat depth `pocketDepth`; male = mirrored geometry, V-carve
  of the *complement* (boundary rectangle grown by `maleBoundaryMargin` minus the shapes),
  depths shifted up by `maleStartDepth` and reduced by `glueGap`, clearing outside the plug.
* **Fluting**: along each open (or closed) vector, Z ramps from `startDepth` to `cutDepth`
  over `rampFraction` of the length at the start/end/both (linear or smooth cosine), multi-pass.
* **Texture**: deterministic PRNG (seeded) produces strokes along `angle` spaced by `spacing`
  with random length/offset/depth (V-bit or ball), clipped to the boundary, each stroke a
  shallow dip (plunge-ramp in, ramp out).
* **Relief3D**: STL → heightmap (rasterise triangles, max Z per cell) scaled to `depth`.
  Roughing: z-level slices; at each level the region where the model is below that level is
  pocketed (raster/offset) leaving `allowance`. Finishing: raster lines across the heightmap,
  tool-shape-compensated drop-cutter Z at each sample (flat/ball/V profiles), points thinned
  by collinearity tolerance.

## Preview & simulation

2D overlay of toolpaths on the canvas (rapids dashed). 3D: `Heightfield` (material frame,
depth per cell) carved by sweeping the tool profile along moves; rendered in SceneKit as a
mesh. Time = Σ(cut length / feed) + Σ(rapid length / profile rapid rate) + tool changes.

## Post processor

`PostProfile` (Codable) holds every textual decision: units, decimals, comment style,
preamble, tool-change template lines, optional `G43 H{T}`, spindle on + `G4 P{SECONDS}` dwell,
arc output mode (incremental IJ / absolute / linearise), helical arcs, modal suppression,
footer template, machine limits, rapid rate. `TemplatePostProcessor` renders:

```
( header: job, post name/version, material WxHxT, Z zero, XY origin, tool list )
G20 | G21
G90 G17 G40 G49 G80 G94        (one per line)
M5 / (Change to Tool: <name>) / T<n> M6 [G43 H<n>]
G0 Z<safe>  then  M3 S<rpm> / G4 P<s>
...moves (G0 always preceded by Z retract to safe Z when XY changes)...
G0 Z<safe> / M5 / G0 X<home> Y<home> / M30
```

Unit conversion happens in the post when profile units ≠ document units. Shipped profiles:
Avid PRO6096 Mach4 (inch, mm), Generic GRBL (mm, `M0` pause for tool change). `GCodeValidator`
checks travel extents, depth below spoilboard, rapids under safe Z, RPM range.

## Testing

swift-testing via `scripts/test.sh`. Pure-function generators get golden-value tests
(depths, offsets, pass counts, safe-Z invariants) in both Z-zero modes and all XY origins; the
post gets golden G-code snippets; importers get small fixture files written in tests.
The validator runs over every generated program in tests (no rapid below safe Z, no cut
below spoilboard tolerance).

## Acceptance

1. `swift build` + `scripts/test.sh` green; `scripts/bundle.sh` produces a launching
   `dist/Kerf.app`.
2. Workflow: new job → draw/import → profile + pocket + V-carve toolpaths → preview →
   export `.tap`.
3. Air cut on the Avid PRO6096 (Mach4) with Z zero set 1" above the material, both Z-zero
   modes, verifying tool-change prompts, safe-Z rapids and home move.
