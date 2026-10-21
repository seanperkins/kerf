# Kerf

Kerf is a native macOS (Apple Silicon, macOS 14+) CAD/CAM app for 2D, 2.5D and basic 3D routing.
It generates G-code for the Avid CNC PRO6096 (Mach4) and replaces VCarve Pro for that
machine.

- **Design:** import SVG (incl. text and embedded images), DXF, EPS, AI and PDF vectors, tracing
  images (JPG/PNG/BMP/TIF/GIF/WebP) and STL/OBJ/COLLADA models (or their parts as flat outlines);
  browse your own clipart folders; export SVG, DXF, PDF, EPS and AI. Job notes are saved with the file.
  Jobs can be two-sided or span several material sheets, start from saved templates, and numeric
  fields accept expressions and linked document variables (`=thickness/2`, `1/4in`). Drawing tools include shapes,
  polylines, Bézier pen, text in any installed font, node editing, transforms, align/distribute,
  booleans, offset, layers, snapping and undo/redo. **Gadgets** (Gadgets menu) are JavaScript
  add-ons that draw vectors and set up toolpaths; see Gadgets > Gadget API Reference.
- **Toolpaths:** Profile (tabs, ramps, leads, last pass, start point, cut order), Pocket (offset/raster,
  several clearance tools), Drilling (peck), Hole Milling (helical bores and threads), V-Carve, Photo
  V-Carve, Prism, Quick Engrave, Chamfer, V-bit and straight-wall Inlay, Fluting, Texture, Moulding and
  3D relief (roughing + finishing, rest machining, two-sided, projection onto the model). Toolpaths can
  be merged, saved as templates by layer, and checked against keep-out zones; a tool database holds
  folders, per-material feeds and a feeds calculator. Toolpaths > Preview G-code File… shows another job's G-code.
- **Layout:** true-shape nesting with overflow onto extra sheets, clamp and fixture keep-out
  zones, part labels, production plates (one design repeated per CSV row with `{Field}` text),
  a printable job sheet, material and bed checks, and tiled G-code for jobs
  larger than the bed (Design > Layout, File > Export Job Sheet…, Toolpaths > Save Tiled G-code…).
- **Preview and output:** 2D overlay, 3D material-removal simulation and time estimates, and
  printing of the 2D design. A
  data-driven post (JSON profiles) ships with Avid Mach4 inch/mm and Generic GRBL (mm), and output
  goes through a built-in G-code validator. The 2D and 3D views can be shown side by side, and
  File > Recover Unsaved Work… restores autosaved work after a crash.

Feature status against VCarve Pro is tracked in [docs/PARITY.md](docs/PARITY.md) (196 features: 172 done,
7 partial, 17 missing, every P1 item done). [TESTING.md](TESTING.md) §3 walks through what is new since the
first test build.

## Build and run

Requires an Apple Silicon Mac on macOS 14+ with Swift 6 (Command Line Tools are enough;
Xcode works too). Install the tools with `xcode-select --install` if `swift --version` fails.

```sh
git clone https://github.com/seanperkins/kerf.git && cd kerf
scripts/bundle.sh && open dist/Kerf.app
```

The bundle is ad-hoc signed, so macOS treats a copy downloaded from elsewhere as unverified.
A locally built one opens normally.

```sh
scripts/build.sh            # debug build
scripts/test.sh             # swift-testing suite
scripts/bundle.sh           # release build → dist/Kerf.app (ad-hoc signed)
scripts/run.sh              # debug bundle + launch
```

- [TESTING.md](TESTING.md): guided test and the safe air-cut procedure.
- `docs/DECISIONS.md`: design decisions.
- `THIRD_PARTY.md`: vendored Clipper2 and Boost.Polygon.
