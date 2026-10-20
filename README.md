# Kerf

Kerf is a native macOS (Apple Silicon, macOS 14+) CAD/CAM app for 2D, 2.5D and basic 3D routing.
It generates G-code for the Avid CNC PRO6096 (Mach4) and replaces VCarve Pro for that
machine.

- **Design:** import SVG (incl. text and embedded images), DXF, EPS, AI and PDF vectors, tracing
  images (JPG/PNG/BMP/TIF/GIF/WebP) and STL/OBJ/COLLADA models; export SVG, DXF, PDF, EPS and AI.
  Jobs can be two-sided or span several material sheets, start from saved templates, and numeric
  fields accept expressions and document variables (`=thickness/2`, `1/4in`). Drawing tools include shapes,
  polylines, Bézier pen, text in any installed font, node editing, transforms, align/distribute,
  booleans, offset, layers, snapping and undo/redo.
- **Toolpaths:** Profile (tabs, ramps, leads), Pocket (offset/raster, clearance tool), Drilling (peck),
  V-Carve, Inlay, Fluting, Texture and 3D relief (roughing + finishing).
- **Preview and output:** 2D overlay, 3D material-removal simulation and time estimates, a printable
  HTML job sheet, and printing of the 2D design. A
  data-driven post (JSON profiles) ships with Avid Mach4 inch/mm and Generic GRBL (mm), and output
  goes through a built-in G-code validator.

## Build and run

Requires the Swift Command Line Tools; Xcode is not needed.

```sh
swift build                 # debug build
scripts/test.sh             # swift-testing suite
scripts/bundle.sh           # release build → dist/Kerf.app (ad-hoc signed)
scripts/run.sh              # debug bundle + launch
```

- [TESTING.md](TESTING.md): guided test and the safe air-cut procedure.
- `docs/DECISIONS.md`: design decisions.
- `THIRD_PARTY.md`: vendored Clipper2 and Boost.Polygon.
