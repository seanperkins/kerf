# Testing Kerf

## 1. Open the app

- The app is at `dist/Kerf.app`. To rebuild it, run `scripts/bundle.sh` (release build, ad-hoc signed).
- **First launch:** the app is ad-hoc signed, not notarised. Right-click `Kerf.app` → **Open** → **Open**.
  If macOS still blocks it, go to System Settings → Privacy & Security → "Open Anyway".
- The **Welcome** window opens at launch (Help ▸ Welcome to Kerf reopens it). "Open the Sample Sign" opens an
  untitled copy of `sign.kerf`; Help ▸ Kerf Help (⌘?) has a topic for every form.
- Sample files are in `samples/`:

| File | What it is |
|---|---|
| `sign.kerf` | 24 × 12 × 0.75 in sign with Pocket, V-Carve, Drilling and Profile toolpaths already set up |
| `sign.tap` | The G-code for that sign, from the "Avid PRO6096 Mach4 (inch)" post, with no validator errors |
| `sign.svg` | The sign's vectors on four layers (Outline, Pocket, Text, Drill) |
| `bracket-plate.dxf` | 8 × 5 in plate with bolt holes, a slot and a bore |
| `relief.stl` | 75 mm square relief (dome and waves) for the 3D toolpath |

To regenerate the samples, run `KERF_WRITE_SAMPLES=1 scripts/test.sh --filter SampleFiles`.

## 2. Ten-minute test script

1. **Open the sample.** File → Open `samples/sign.kerf`. Toolpath results are not saved in the
   file, so run Toolpaths → **Calculate All** (⌘R). The four toolpaths appear in the sidebar with
   their tools and estimated times, and the toolpaths are drawn over the design.
2. **Job Setup** (⇧⌘J). Switch the Z zero between Material top and Spoilboard, and try a few XY
   origins (corners or centre). Leave the settings at Material top and lower left.
3. **Preview.** Open the 3D preview (⌥⌘3) and press Play. The pocket, carved letters, holes and the
   cut-out with tabs should look right. Try scrubbing and changing the speed, stepping one move at a
   time, and "run to next retract". Try the scope picker (all / visible / selected toolpaths), the
   material palette (wood type, painted top), the ruler (click the stock twice to measure), the
   camera button (save a PNG) and the stopwatch (acceleration and calibration). Use the cube menu for
   Top / Front / Left / Isometric views and Orthographic, and the Show menu to draw toolpath lines,
   rapids and vectors in 3D. With the pencil button, click points on the stock to draw a polyline
   (click the first point to close it, Return to finish); it appears in the 2D view too. The arrow
   button selects vectors by clicking them in 3D. Switch back with ⌥⌘1.
4. **Export.** File → Export G-code… (⇧⌘E) and save `test.tap`. It should match `samples/sign.tap`
   (only the date or job name may differ). Toolpaths → Check Toolpaths… (⇧⌘K) should report no errors.
5. **Import.** Make a new document (⌘N). Use File → Import… (⇧⌘I) to import `bracket-plate.dxf`.
   The plate and its six inner features should appear.
   Then import `Tests/Fixtures/CADCore/outline-with-gap.dxf`: it arrives as one open vector, and the
   Import alert names the layer (Cabinet) and a gap of about 0.2 mm (0.0079 in), not joined at 0.0005 in.
6. **Draw.** Use the canvas tools (V select, N node edit, R rectangle, C circle, E ellipse, L line,
   P Bézier pen, T text). In the Arrange menu, try Align, Boolean (union/subtract/intersect),
   Offset…, Mirror, Rotate, Group/Ungroup and Join/Close vectors. Use ⌘Z/⇧⌘Z to undo and redo.
   Type some text in a font you have installed.
7. **Each toolpath type.** Select vectors, then choose Toolpaths → New Toolpath → …:
   - **Profile** on the plate outline: outside, tabs on, ramp on. Then edit tabs on the canvas
     (Tabs → Placement: Manual → Edit on Canvas).
   - **Pocket** on the slot, with offset and then raster clearing.
   - **Drilling** on the bolt holes, with peck drilling on.
   - **V-Carve** on some text, with and without a flat-bottom clearance tool.
   - **Inlay (Pocket + Plug)…** on a simple shape. The wizard creates a female pocket and a plug
     (the plug is disabled; export it as its own file).
   - **Fluting** on an open line, and **Texture** on a rectangle.
   - **3D:** import `relief.stl`. The "Place 3D Model" dialog creates Roughing and Finishing toolpaths.
     In the inspector, try Offset roughing, the Offset/Spiral finishing patterns, "Rest after" a
     larger ball nose, "Combine with" a second model, and "Two-Sided" (one toolpath per side).
     On a Fluting or Profile toolpath, "Project onto 3D" drops it onto the model's surface.
   Press Calculate All, then check the 2D overlay and the 3D preview for each one.
8. **Save All Toolpaths…** (⌥⌘S): try "one file per toolpath" in a scratch folder.
9. **Tool Database** (⇧⌘T): add or edit a tool. Tools are stored in
   `~/Library/Application Support/Kerf/`.
10. **Round trip.** Save the document as a `.kerf` file, close it and open it again.

### More file and job features

- **Job sheet:** File → Job Sheet… saves an HTML page (material, origin, tools, toolpaths, times,
  picture) and opens it in the browser for printing. File → Print… / Print at Actual Size… print
  the 2D design.
- **More imports:** File → Import… also takes PDF/AI vectors, JPG/PNG/… tracing images (edit them in
  the Design sidebar's Images section: fade, crop, size), OBJ and COLLADA (.dae, e.g. exported from
  SketchUp) models. Export Vectors… writes PDF, EPS or AI by file extension.
- **Templates:** File → Save as Template…, then File → New from Template.
- **Job Setup:** Plunge Z, datum offset, and a two-sided job (Design → Show Bottom Side, ⇧⌘B).
  Design → Sheets adds more material sheets; each sheet exports its own G-code.
- **Variables:** Design → Document Variables…; type `=thickness - 0.05` or `1/4in` in any number field.

## 3. New since first build

The first test build was commit `2ea022c`. These steps cover what was added after it; each takes a
minute or two. Use `samples/sign.kerf` (or a new document) unless a step says otherwise.

1. **More toolpaths.** Toolpaths → New Toolpath now also has Quick Engrave, Chamfer, Hole Milling
   (helical bore; turn on threads), Prism Carve, Photo V-Carve (needs a tracing image), Straight-Wall
   Inlay (Pocket + Plug) and Moulding (pick a rail and a profile vector). Make one of each and press
   Calculate All. On a Profile, try a separate last pass, start point, cut order, sharp corners and
   open-vector left/right offset; on a Pocket or V-Carve, add a second clearance tool.
2. **Merging and templates.** Select two toolpaths that use the same tool and choose Toolpaths → Merge
   With Next Toolpath, then Split Merged Toolpath. Save Toolpath Template…, then Apply Toolpath
   Template… in a new document with the same layer names.
3. **Tools.** Tool Database… (⇧⌘T): tools sit in folders, have per-material feeds and a feeds
   calculator. In a toolpath's inspector, edit the tool's feeds for that toolpath only.
4. **Layout.** Design → Layout → Nest Parts… on the bracket plate copied several times (parts that do not
   fit spill onto extra sheets). Then try Clamps and Fixture Holes…, Toolpaths → Keep-Out Zones… (export
   refuses cuts in a zone), Label Parts…, and Production Plates… with a two-row CSV and `{Name}` in
   a text object. Toolpaths → Save Tiled G-code… splits a job longer than 96 in into bed-sized tiles.
5. **Drawing.** Vectors menu: Dog-bone Fillets…, Fillet / Chamfer Corners…, Rectangular and Circular
   Array…, Copy Along Vector…, Trim Tool, Extend to Nearest Vector, Fit Curves to Vectors…, Text on
   Curve / Arc…, Fit Text to Box…, Convert Text to Curves, Distort Envelope on Canvas and Validate
   Vectors… (problem spots are marked on the canvas). Drag guides out of the rulers and snap to them;
   use the measure tool; while drawing a rectangle, type `3,2` and Return.
6. **Files.** File → Import… a PDF and a JPG (trace it with Vectors → Trace Bitmap…). Export Vectors…
   as PDF/EPS/AI. Save as Template…, then New from Template. File → Clipart… browses a folder of your own
   files. File → Import 3D Model as 2D Parts… flattens a COLLADA/OBJ model into outlines. Toolpaths →
   Preview G-code File… draws a `.tap` from another job.
7. **Job setup.** Job Setup… (⇧⌘J): Plunge Z, datum offset, two-sided job (Design → Show Bottom Side),
   and Design → Sheets for a multi-sheet job. Design → Document Variables… and type `=thickness/2` in a
   depth field.
8. **3D.** With `relief.stl` placed: Offset roughing, Offset/Spiral finishing, Rest after a larger tool,
   Combine with a second model, Two-Sided, and "Project onto 3D" on a Fluting toolpath.
9. **Preview.** In the 3D preview (⌥⌘3): scope picker, material palette, ruler, PNG snapshot,
   stopwatch calibration, camera presets, toolpath lines/rapids/vectors, and the pencil and arrow tools
   for drawing and selecting vectors in 3D. View → Show 2D and 3D Side by Side.
10. **Gadgets and help.** Gadgets menu: run a bundled gadget and open the Gadget API Reference. Help →
    Kerf Help (⌘?), Keyboard Shortcuts, Welcome to Kerf. File → Recover Unsaved Work… after a force-quit.
11. **Job sheet.** File → Export Job Sheet… and check the tools, times, part labels and picture.

Every toolpath in steps 1–8 should calculate without an error, and Check Toolpaths… (⇧⌘K) should
report no errors for the sample. The status of every VCarve Pro feature is in `docs/PARITY.md`.

## 4. On the machine (Avid PRO6096, Mach4)

**Dry run in Mach4 (no cutting):**
1. Load the `.tap` file. Check the header comments for the job, the tools, the material size and
   the Z-zero mode, and check that they match the job you set up.
2. Look at the toolpath display. The part should sit inside the material outline at the chosen
   origin. No moves should go off the bed (X 0–60 in, Y 0–96 in), and the lowest Z should be
   what you expect. With Material-top zero, the deepest cut is −thickness minus any cut-through
   allowance. With Spoilboard zero, it is about Z 0.

**Air cut (always do this before the first real cut):**
1. Secure the material and zero X/Y at the origin you chose in Job Setup.
2. Zero Z with the touch plate as usual, then **jog up 1–2 in and set Z zero there**. The whole
   program now runs in the air.
3. **Leave the spindle off** (disable it or keep the VFD off). The program still sends M3/S, so
   watch that nothing spins.
4. Run the program with feed override around 50%. Keep a hand on E-stop. Check that it pauses
   with "Change to Tool" at each M6. Check that it retracts to safe Z before every rapid move.
   Check that the cut order is pocket, carve, drill, then profile last.
5. If everything looks right, re-zero Z on the real surface (material top or spoilboard, matching
   Job Setup), turn the spindle on and cut. Run the first real cut at reduced feed override.

## 5. Known limitations and stubs

- The app is ad-hoc signed and not notarised (Gatekeeper warns on first launch). It has no app icon.
- Finder / Quick Look thumbnails of `.kerf` files come from the bundled extension
  (`Contents/PlugIns/KerfThumbnail.appex`). macOS picks it up once the app has been launched from
  its final place (e.g. /Applications); `pluginkit -m -i com.seanperkins.kerf.thumbnail` shows whether
  it is registered. Only files saved by this version carry the picture.
- Toolpath results are not stored in `.kerf` files. After opening a file, run Calculate All
  (export also recalculates automatically).
- 3D roughing needs an end mill in the library.
- EPS import only handles a minimal set of path operators (no PostScript programs). PDF-based `.ai`
  files are rejected; save them as SVG instead. DXF splines are approximated with curves.
- "Group by tool" is off by default, so the cut order is the toolpath list order. When it is on,
  it never moves profiles ahead of other toolpaths.
- Inlay plugs are generated in place over the pocket. Export the plug as its own program and cut
  it on a separate board.
- Tool changes are manual (M5, comment, T#M6). G43 H# is off unless you turn it on in the profile.
- App time estimates model acceleration (default 15 in/s², one value for all axes) and allow 90 s per tool
  change; calibrate them in the 3D preview (stopwatch button). The estimate in the G-code header is
  still length / feed.
- The GRBL profile is untested on real hardware.
