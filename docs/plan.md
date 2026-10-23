# LoftLine work plan

Ordered by dependency; items in the same phase run in parallel (see `OWNERSHIP.md`).
Every item: TDD where practical, `swift build` + `scripts/test.sh` green, conventional commit.

## Phase 0 — scaffold (done)
Package, vendored Clipper2 + Boost.Polygon Voronoi, CGeom C API, shared models, op stubs,
post profile types, minimal app, bundle script, docs.

## Phase 1 — parallel workstreams

**cad-io**
1. SVG import (paths incl. arcs → cubic/arc, shapes, transforms, viewBox/units).
2. DXF import (LINE, ARC, CIRCLE, LWPOLYLINE bulges, POLYLINE, SPLINE approx, $INSUNITS).
3. SVG + DXF export. 4. TextOutliner (CoreText). 5. `PathOps.joinOpenPaths`, close vectors.
6. Node-edit helpers (insert/delete node, segment → curve), align/distribute math. 7. EPS (optional).

**cam-2d**
1. Support: loop ordering, safe-Z linking, plunge/ramp builders, arc re-fitting.
2. Profile (sides, passes, climb/conv, allowance) → tabs → ramps → lead-in/out.
3. Pocket offset → raster → clearance tool rest machining. 4. Drill (peck).
5. Fluting. 6. Texture.

**cam-vcarve**
1. Medial axis extraction from `GeomKernel.voronoi` (inside filtering, chaining).
2. V-carve depth mapping, flat depth + flat-area clearance. 3. Inlay male/female.

**cam-3d**
1. STL import (binary/ASCII). 2. Mesh → heightmap. 3. Drop-cutter (flat/ball/V).
4. Raster finishing. 5. Z-level roughing.

**post**
1. `TemplatePostProcessor` header/preamble/tool change/spindle/moves/footer with golden tests.
2. Arc output modes + linearisation, unit conversion. 3. Safe-Z enforcement.
4. `GCodeValidator`. 5. User profile JSON loading from Application Support.

**preview**
1. Heightfield simulator (flat/ball/V sweeps). 2. Time estimator.
3. SceneKit material view. 4. 2D toolpath overlay renderer (Core Graphics paths for canvas).

**app-shell**
1. Document window model (`LoftLineProject` + undo manager), open/save `.loftline`.
2. Canvas: pan/zoom, grid, snapping, selection, move/scale/rotate/mirror.
3. Drawing tools (rect, rounded rect, circle, ellipse, polygon, star, polyline, Bézier, text).
4. Layers panel, Job Setup sheet, tool database editor.
5. Toolpath panel: operation editors per kind, recalc, visibility.
6. Export G-code (per toolpath / combined grouped by tool), post selection.

## Phase 2 — integration
Wire everything in the app, end-to-end tests (document → toolpaths → G-code → validator) for
both Z-zero modes, bundle, smoke-launch, README with Avid air-cut checklist.
