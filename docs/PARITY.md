# VCarve Pro parity inventory

Kerf against the public VCarve Pro 12.5 feature set, built from Vectric's public product page and online help only (see Sources). Status is judged from Kerf's code and tests: **done** = works end to end including the UI; **partial** = engine or UI only, or a subset of the options; **missing** = not implemented. Priority: **P1** = matters for typical Avid sign, part, inlay or 3D jobs; P2 = useful; P3 = niche or out of scope (for example rotary).

Totals: 177 features. 156 done, 11 partial, 10 missing. P1: 64 done, 0 partial, 0 missing.

Round 2 (2026-10-20): every partial and missing item was re-checked against the code and is unchanged; the full suite passed (774 tests). Fourteen items were added from the public feature list (marked *r2* in notes).

| id | area | feature | status | priority | notes |
|---|---|---|---|---|---|
| `draw-basic-shapes` | drawing | Basic shape tools (rectangle, rounded rect, circle, ellipse, polygon, star) | done | P1 | Sources/KerfApp/Model/DrawingTools.swift, Sources/CADCore/Geometry/ShapeFactory.swift; EditingPanels numeric create; Tests/KerfAppTests/CanvasModelTests.swift |
| `draw-line-polyline` | drawing | Line / polyline tool | done | P1 | DrawingTools.polyline; CanvasEvents click-built tools |
| `draw-arc-tool` | drawing | Arc drawing tool (3-point / centre-radius) | done | P2 | CanvasTool.arc |
| `draw-bezier-curve` | drawing | Bézier pen and smooth curve | done | P2 | Sources/CADCore/Editing/PenPath.swift, DrawingTools.smoothCurve; EditingTests |
| `draw-freehand` | drawing | Freehand sketch tool | done | P3 | CanvasTool.freehand |
| `draw-quick-keys` | drawing | Typed quick-key entry while drawing (length/angle, W,H, radius) | done | P2 | Typed length/angle/size entry while drawing |
| `draw-node-edit` | drawing | Node editing (move/insert/delete nodes, smooth/corner, line↔curve, break) | done | P1 | Sources/CADCore/Editing/PathNodes.swift, Canvas/CanvasNodeEvents.swift, Panels/EditingPanels.swift; EditingTests, EditingRenderTests |
| `draw-node-set-start` | drawing | Set vector start point in node edit | done | P2 | Node inspector "Set Start"; Profile honours it via ProfileStartPoint.vectorStart |
| `draw-node-span-arc` | drawing | Convert span to arc / join and align nodes (match X/Y) | partial | P3 | "To Arc" and Align X/Y done; no mirror-mode node editing |
| `draw-transform-handles` | drawing | On-canvas move / scale / rotate handles | done | P1 | Sources/CADCore/Editing/TransformHandles.swift, Canvas/CanvasEditingOverlay.swift; EditingRenderTests |
| `draw-numeric-transform` | drawing | Numeric move / set size / rotate / scale | done | P1 | Panels/InspectorView.swift, TransformCommands (DesignCommands.swift) |
| `draw-distort-shear` | drawing | Distort / shear / skew | partial | P3 | Shear works; envelope corners are numeric, not draggable |
| `draw-mirror` | drawing | Mirror (selection, copy, about material centre) | done | P2 | Mirror copy and about material centre |
| `draw-align-distribute` | drawing | Align and distribute | done | P1 | DesignCommands.align/distribute/distributeSpacing; KerfCommands Align menu; EditingCommandTests |
| `draw-booleans` | drawing | Weld / subtract / intersect | done | P1 | DesignCommands.boolean, CADCore/Geometry/PathOps.swift; GeometryOpsTests |
| `draw-trim` | drawing | Interactive trim and trim-to-boundary | done | P2 | CanvasTool.trim and trim to boundary |
| `draw-extend` | drawing | Extend vectors to boundary | done | P3 | Extend to boundary |
| `draw-offset` | drawing | Offset vectors (inside/outside, round/sharp) | done | P1 | DesignCommands.offset, OffsetSheet in ExportGCodeSheet.swift; GeometryOpsTests |
| `draw-offset-open` | drawing | Offset open vectors (one side / both sides) | done | P3 | Offset sheet handles open vectors (one side / both) |
| `draw-inlay-offset` | drawing | Inlay offset helper (offset for traditional end-mill inlays) | done | P3 | Inlay offset helper |
| `draw-fillet-chamfer` | drawing | Fillet and chamfer corners | done | P2 | Fillet and chamfer corners |
| `draw-dogbone` | drawing | Dog-bone / T-bone fillets | done | P1 | Dog-bone / T-bone fillets (Vectors menu, drawing sheet); DrawingDogboneTests |
| `draw-smart-snap` | drawing | Smart snapping (nodes, midpoints, centres, grid) | done | P1 | Sources/CADCore/Editing/SnapEngine.swift; EditingTests |
| `draw-guides` | drawing | Guide lines and snap to guide/extension lines | done | P2 | Document.guides, snap to guides and node extension lines |
| `draw-rulers-grid` | drawing | Rulers, grid and cursor readout | done | P2 | CanvasDrawing.drawRulers, JobSetupSheet grid spacing, ContentView cursor readout |
| `draw-measure` | drawing | Measure tool (distance, angle, radius) | done | P2 | CanvasTool.measure (distance, angle, radius) |
| `draw-array-linear` | drawing | Rectangular array copy | done | P1 | Rectangular array sheet (Vectors menu) |
| `draw-array-circular` | drawing | Circular array copy | done | P2 | Circular array sheet |
| `draw-copy-along` | drawing | Copy along vector | done | P3 | Copy along vector |
| `draw-copy-paste` | drawing | Copy, cut, paste, duplicate, nudge | done | P1 | ShapeClipboard (EditingCommands.swift), CanvasEvents.keyDown nudge; EditingCommandTests |
| `draw-selection-tools` | drawing | Selection helpers (select all, by layer, open vectors, duplicates, similar, invert) | partial | P3 | *r2* Edit > Select All and layer "Select Shapes on Layer" only; no select-open/duplicate/similar/invert commands |
| `draw-join-close` | drawing | Join / close open vectors | done | P1 | DesignCommands.join/close, PathOps.joinOpenPaths |
| `draw-curve-fit` | drawing | Fit curves to vectors (smooth polylines into arcs/Béziers) | done | P2 | Fits lines and arcs (not Béziers) |
| `draw-vector-validator` | drawing | Vector validator (open, duplicate, self-intersecting, zero-length) | done | P1 | Vector validator with canvas highlight markers |
| `draw-duplicate-overlap` | drawing | Find/remove duplicate and overlapping vectors | done | P2 | Duplicate / overlapping vector finder |
| `draw-layers` | drawing | Layers (visibility, lock, colour, reorder, move-to-layer) | done | P1 | Panels/SidebarView.swift layers tab, CADCore Document layers; ProjectModelTests |
| `draw-grouping` | drawing | Group / ungroup / combine / break apart | done | P1 | CADCore/Editing/Grouping.swift, DesignCommands.combine/explode |
| `draw-lock-objects` | drawing | Lock / unlock individual objects | done | P2 | *r2* Shape.isLocked, inspector "Locked" toggle, sidebar lock icon; layer lock in SidebarView |
| `draw-nested-groups` | drawing | Nested groups and deep ungroup | done | P3 | Shape.innerGroupIDs; Ungroup one level / Ungroup All Levels |
| `draw-dimensions` | drawing | Dimension objects (linear, angular, radial) | done | P3 | Document.dimensions, CanvasTool.dimension |
| `draw-text-basic` | drawing | Text in any installed font with cap-height sizing | done | P1 | CADCore/Geometry/TextOutliner.swift, DrawingTools text; TextOutlinerTests |
| `draw-text-editable` | drawing | Editable text objects (re-open to change string/font/size, alignment, spacing) | done | P1 | Shape.text (TextSpec) live text, re-editable in the inspector |
| `draw-text-to-curves` | drawing | Convert live text to curves | done | P1 | *r2* Vectors > Convert Text to Curves, VectorCommands.convertTextToCurves |
| `draw-text-autolayout` | drawing | Auto-layout text to fit a box | done | P2 | Auto-layout text to a box |
| `draw-text-on-curve` | drawing | Text on a curve / arc text / bend text | done | P2 | Text on a curve (output is plain vectors) |
| `draw-single-line-fonts` | drawing | Single-stroke (engraving) fonts | done | P2 | Kerf Single Line stroke font (own design) |
| `draw-kerning` | drawing | Interactive kerning / character spacing | partial | P3 | TextSpec.letterAdjustments edited numerically in the inspector, not by dragging |
| `draw-trace-bitmap` | drawing | Trace bitmap (image → vectors) | done | P2 | BitmapTracer + Trace Bitmap sheet (image not kept in the document) |
| `draw-vector-texture` | drawing | Vector texture generator | done | P3 | Vector texture generator |
| `draw-boundary-vector` | drawing | Create boundary around selection | done | P3 | Boundary vector around selection |
| `draw-plate-maker` | drawing | Plaque / plate border generator | done | P3 | Plate maker |
| `io-svg-import` | io | SVG import | done | P1 | CADCore/IO/SVGImporter.swift; IOSVGTests |
| `io-dxf-import` | io | DXF import | done | P1 | CADCore/IO/DXFImporter.swift; IODXFTests; samples/bracket-plate.dxf |
| `io-eps-import` | io | EPS import | done | P2 | CADCore/IO/EPSImporter.swift; IOEPSTests |
| `io-ai-pdf-import` | io | AI and PDF import (vectors, embedded images) | done | P2 | AI/PDF vector import |
| `io-svg-text` | io | SVG text and image elements on import | done | P3 | SVG <text> imported as outlines |
| `io-bitmap-import` | io | Bitmap import (JPG/PNG/BMP/TIF/GIF/WebP) | done | P2 | Document.images (PlacedImage), drawn under the vectors |
| `io-image-crop` | io | Picture editing: position, size, crop and fade a placed bitmap | done | P3 | *r2* PlacedImage.crop/opacity, Panels/ImagePanels.swift image editor |
| `io-stl-import` | io | STL 3D model import | done | P1 | CADCore/IO/STLImporter.swift, ModelPlacementSheet; STLImporterTests |
| `io-obj-3d-import` | io | OBJ / other 3D formats import | done | P2 | OBJ model import |
| `io-skp-import` | io | SketchUp import | partial | P3 | No .skp reader (needs Trimble SDK); SketchUp COLLADA export imports as a 3D model or, via File > Import 3D Model as 2D Parts…, as flat part outlines (CADCore/IO/MeshParts.swift; IOMeshPartsTests, IOModelPartsTests) |
| `io-vector-export` | io | Vector export (SVG, DXF) | done | P1 | CADCore/IO/SVGExporter.swift, DXFExporter.swift; KerfCommands Export Vectors |
| `io-eps-ai-export` | io | EPS / AI / PDF vector export | done | P3 | EPS / AI export |
| `io-project-file` | io | Native project file with versioning | done | P1 | CADCore/Persistence/KerfFile.swift; IOKerfFileTests, DocumentTests |
| `io-job-templates` | io | Job templates (saved material setup + layers + toolpaths) | done | P2 | File > New from Template / Save as Template |
| `io-two-sided-setup` | io | Two-sided job setup (flip axis, per-side Z zero, both-sides view) | done | P2 | JobSetup.twoSided, Layer.side, side switching; preview simulates one side |
| `io-material-setup` | io | Material setup (size, thickness, Z zero top/bed, XY datum, safe Z, home) | done | P1 | CADCore/Model/JobSetup.swift, Panels/JobSetupSheet.swift; MachineCoordinatesTests |
| `io-material-plunge-z` | io | Separate plunge Z (Z2) and XY datum offset | done | P2 | JobSetup.plungeGap |
| `io-model-position` | io | Model position in material (gap above/below) | done | P2 | Model placement sheet position/datum; JobSetup.datumOffset |
| `io-multiple-sheets` | io | Multiple sheets per job (different sizes/thicknesses) | done | P2 | Document.otherSheets / MaterialSheet; 3D models and relief stay on the primary sheet |
| `io-document-variables` | io | Document variables in numeric fields | done | P3 | Job Setup and toolpath fields stay linked to expressions with variables (Document.variableLinks, KerfApp/Model/VariableLinks.swift; IOVariableLinkTests); drawing-panel fields are evaluated once |
| `io-units-convert` | io | Unit switching inch↔mm with conversion | done | P1 | KerfApp/Model/UnitScaling.swift; ProjectModelTests |
| `io-setup-sheet` | io | Job / setup sheet (printable report) | done | P1 | Covered by lay-job-sheet (File > Export Job Sheet…); the io job-sheet variant was dropped at merge |
| `io-print` | io | Print 2D design / 3D view | done | P3 | File > Print / Print at Actual Size (2D design only) |
| `io-job-notes` | io | Job notes saved with the file (shown on open, printed on the setup sheet) | done | P3 | Document.notes / showNotesOnOpen, File > Job Notes…, JobSheet "Notes" section; IOJobNotesTests |
| `io-clipart-library` | io | Clipart browser (local folders and online clipart) | partial | P3 | File > Clipart… browses the user's own folders (vectors, 3D models, .kerf) with thumbnails and search (KerfApp/Model/ClipartLibrary.swift; IOClipartTests); no online clipart and no bundled clipart |
| `io-post-processors` | io | Post processor selection and custom posts | done | P1 | PostCore/Profiles/BuiltInPosts.swift, PostProfileStore; PostGoldenTests, PostProfileTests |
| `io-gcode-validator` | io | G-code safety validation | done | P1 | PostCore/Validation/GCodeValidator.swift, ValidationSheet; PostValidatorTests |
| `io-save-toolpaths` | io | Save toolpaths (single, combined, per tool) | done | P1 | Panels/SaveAllToolpathsSheet.swift, Model/GCodeBatchExport.swift; AdvancedToolpathDocumentTests |
| `io-file-thumbnails` | io | File thumbnails / Quick Look | done | P3 | Quick Look thumbnail extension built by scripts/bundle.sh (Extensions/QuickLookThumbnail) from a PNG embedded in each saved file, plus the Finder custom icon; IOQuickLookThumbnailTests |
| `tp-profile-basic` | toolpaths-2d | Profile: inside/outside/on, climb/conventional, allowance, multi-pass | done | P1 | CAMCore/Ops2D/ProfileOperation.swift; Ops2DProfileTests; e2e sign |
| `tp-profile-open-sides` | toolpaths-2d | Profile open vectors left/right | done | P2 | ProfileParameters.openVectorSide, Ops2D/Support/OpenOffset.swift; Ops2DOpenSideTests |
| `tp-profile-last-pass` | toolpaths-2d | Separate last pass (allowance, reverse direction) | done | P1 | ProfileParameters.lastPass (allowance, reverse, full depth); ProfileOperation; Tests/CAMCoreTests/Ops2DLastPassTests.swift |
| `tp-pass-editor` | toolpaths-2d | Pass depth editor (exact step, custom passes, last-pass thickness) | done | P2 | DepthSettings.customPasses / exactStep, PassEditor form; Ops2DPassDepthTests |
| `tp-profile-start-point` | toolpaths-2d | Use vector start point / optimise start points | done | P2 | ProfileParameters.startPoint, Ops2D/Support/StartPoints.swift; Ops2DStartPointTests |
| `tp-profile-order` | toolpaths-2d | Profile ordering (selection order, left→right, bottom→top, grid) | done | P2 | ProfileParameters.order, Ops2D/Support/ProfileOrdering.swift; Ops2DProfileOrderTests |
| `tp-tabs-auto` | toolpaths-2d | Tabs: automatic count/spacing, rectangular or triangular (3D) | done | P1 | TabSettings, Ops2D/Support/PassShaping.swift; Ops2DProfileTests |
| `tp-tabs-manual` | toolpaths-2d | Tabs: on-canvas placement and editing | done | P1 | Model/TabEditor.swift, Panels/TabEditingBanner.swift; Ops2DManualTabTests |
| `tp-ramps` | toolpaths-2d | Ramps (smooth, zig-zag, spiral) by distance/angle | done | P1 | RampSettings, PassShaping.swift; Ops2DProfileTests |
| `tp-leads` | toolpaths-2d | Lead-in/out (linear, arc) and overcut | done | P1 | Ops2D/Support/Leads.swift; Ops2DProfileTests |
| `tp-sharp-corners` | toolpaths-2d | Sharp external corners (square corners) | done | P2 | ProfileParameters.sharpCorners (miter joins); Ops2DSharpCornerTests |
| `tp-pocket-offset-raster` | toolpaths-2d | Pocket: offset and raster with angle, islands | done | P1 | CAMCore/Ops2D/PocketOperation.swift, PocketPlanner.swift; Ops2DPocketTests |
| `tp-pocket-profile-pass` | toolpaths-2d | Pocket profile pass first/last/none | done | P2 | PocketParameters.profilePassFirst; Pocket form None/First/Last; Ops2DPocketProfilePassTests |
| `tp-pocket-multi-tool` | toolpaths-2d | Pocket with multiple clearance tools (rest machining) | done | P1 | PocketParameters.clearanceToolIDs, PocketPlanner.restClearing(fullWalls:); ClearanceToolsEditor; Ops2DPocketMultiToolTests |
| `tp-pocket-ramp-allowance` | toolpaths-2d | Pocket ramp plunges and pocket allowance | done | P1 | PocketParameters.ramp/allowance; Ops2DPocketTests |
| `tp-drilling` | toolpaths-2d | Drilling with peck, dwell, retract | done | P1 | CAMCore/Ops2D/DrillOperation.swift; Ops2DDrillTests |
| `tp-drill-bank` | toolpaths-2d | Drill bank / multi-spindle drilling | missing | P3 | Won't do: the Avid has a single spindle and no drill-bank head (DECISIONS toolpaths-2d, re-confirmed round 2) |
| `tp-helical-hole` | toolpaths-2d | Helical hole milling / thread milling | done | P2 | HoleMillOperation (helical bore + internal thread milling); Ops2DHoleMillTests |
| `tp-quick-engrave` | toolpaths-2d | Quick engrave (follow vector on centreline) | done | P1 | EngraveOperation (OperationKind.engrave), groove width in form + metadata; Ops2DEngraveChamferTests |
| `tp-chamfer` | toolpaths-2d | Chamfer toolpath | done | P1 | ChamferOperation (width or depth, tip clearance, side); ChamferForm; Ops2DEngraveChamferTests |
| `tp-inlay-straight` | toolpaths-2d | Straight-wall (end-mill) inlay toolpath | done | P3 | StraightInlayOperation (matched close(open(S,r),r) outline); Ops2DStraightInlayTests |
| `tp-prism` | toolpaths-2d | Prism (raised bevel) carving | done | P2 | PrismOperation (per-shape depth from inscribed radius); Ops2DPrismTests |
| `tp-moulding` | toolpaths-2d | Moulding toolpath (profile swept along rail) | done | P3 | MouldingOperation: exact 1D drop-cutter for straight rails; curved, cornered and closed rails use the swept-surface heightmap + 2D DropCutter (MouldingSurface); Ops2DMouldingTests, Ops2DMouldingSurfaceTests |
| `tp-fluting` | toolpaths-2d | Fluting with ramp in/out | done | P2 | CAMCore/Ops2D/FlutingOperation.swift; Ops2DFlutingTextureTests |
| `tp-texture` | toolpaths-2d | Texture toolpath | done | P3 | CAMCore/Ops2D/TextureOperation.swift; Ops2DFlutingTextureTests |
| `tp-templates` | toolpaths-2d | Toolpath templates (save/load, auto vector selection) | done | P2 | CAMCore/Templates/ToolpathTemplate.swift, TemplateService, Toolpaths menu; Tests/KerfAppTests/ToolpathTemplateTests.swift |
| `tp-merge` | toolpaths-2d | Merge toolpaths | done | P3 | MergeOperation, Merge With Next / Split Merged commands; MergeToolpathTests |
| `tp-import-toolpaths` | toolpaths-2d | Import toolpaths from another job | done | P3 | Toolpath templates bring toolpath sets across jobs (TemplateService.apply); Toolpaths > Preview G-code File… simulates another job's program on this stock (PostCore GCodeReader, GCodePreviewWindow); PostGCodeReaderTests, GCodePreviewTests |
| `tp-array-copy` | toolpaths-2d | Array copy toolpath | done | P3 | OperationSetup.arrayCopy, ToolpathArray; Array Copies inspector section; Ops2DArrayCopyTests |
| `tp-order-visibility` | toolpaths-2d | Toolpath list: reorder, duplicate, enable, show/hide, recalc, stale status | done | P1 | Panels/SidebarView.swift ToolpathsSidebar/ToolpathRow; ProjectModelTests |
| `tp-tool-database` | toolpaths-2d | Tool database (kinds, cutting data, units, numbers) | done | P1 | CADCore/Model/ToolLibrary.swift, Panels/ToolDatabaseView.swift |
| `tp-tool-groups-materials` | toolpaths-2d | Tool groups and per-material cutting data | done | P2 | Tool.group, Tool.materials, JobSetup.material, CAMContext.tool; ToolDataSections; Ops2DToolDataTests, ToolGroupingTests |
| `tp-feeds-calculator` | toolpaths-2d | Feeds and speeds calculator (chip load) | done | P2 | CAMCore/Tools/FeedsAndSpeeds.swift; tool editor calculator section; Ops2DToolDataTests |
| `tp-tool-db-import-export` | toolpaths-2d | Tool database import/export and sharing between machines | done | P2 | Tool Database > Share: import/export .kerftools (lossless JSON; also reads another Mac's tools.json) and CSV; conflict policy Replace / Keep Both / Skip, unique T numbers; CADCore/Persistence/ToolLibraryExchange.swift; ToolExchangeTests, ToolExchangeModelTests |
| `tp-tool-shapes` | toolpaths-2d | Extra cutter shapes: radiused (bull-nose) end mill, tapered ball nose, form tools | done | P2 | Tool.shape: bull nose (corner radius), tapered ball nose (tip radius + taper angle), form tool (radius vs height outline) with editor, roundover preset and outline view; used by the simulator, 3D drop-cutter, Moulding and engrave width; CADCore/Model/CutterShape.swift; ToolShapeTests, Ops2DToolShapeTests |
| `tp-tool-edit-per-toolpath` | toolpaths-2d | Per-toolpath tool parameter override | done | P2 | OperationSetup.toolOverride via CAMContext.toolOverrides; ToolOverrideSection; Ops2DToolDataTests |
| `tp-arc-output` | toolpaths-2d | Arc (G2/G3) and helical arc output | done | P2 | ArcFitter.swift; PostProfile arcOutput/helicalArcs; PostGoldenTests |
| `tp-tiling` | toolpaths-2d | Toolpath tiling for jobs larger than the bed | done | P3 | Covered by lay-tiling (Toolpaths > Save Tiled G-code…) |
| `tp-keepout` | toolpaths-2d | Keep-out zones | done | P2 | Zones are checked on export, and zones marked "Lift over" re-route every toolpath up and over them (KeepOutAvoidance, last step of AnyOperation.generate); Ops2DKeepOutTests, Ops2DKeepOutLiftTests, KeepOutZoneTests |
| `tp-laser` | toolpaths-2d | Laser add-on toolpaths (line, fill, image) and laser posts | missing | P3 | *r2* Won't do: the Avid is spindle only; a laser post would emit S as power to a router spindle (DECISIONS toolpaths-2d round 2) |
| `vc-basic` | vcarve | V-carve (medial-axis depth from V angle) | done | P1 | CAMCore/OpsVCarve/VCarveOperation.swift, VCarveMedialAxis.swift; VCarveTests |
| `vc-flat-depth` | vcarve | Flat depth with flat-area clearance (offset/raster) | done | P1 | VCarvePocketing.swift, VCarveParameters.flatDepth/flatClearanceToolID; VCarveTests |
| `vc-multi-clearance` | vcarve | Multiple clearance tools for flat areas | done | P2 | VCarveParameters.extraClearanceTools, VCarveEngine.clearFlatArea (rest machining); VCarveParityTests |
| `vc-start-depth` | vcarve | Start depth (carve inside a pocket) | done | P2 | VCarveParameters.startDepth; VCarveTests |
| `vc-corner-sharpen` | vcarve | Corner sharpening | done | P2 | VCarveClearanceTool.cornerSharpen, VCarveEngine.cornerStrokes; VCarveParityTests |
| `vc-multi-pass` | vcarve | Multi-pass deep V-carving | done | P2 | VCarveParameters.passDepth; VCarveTests |
| `vc-inlay` | vcarve | V-carve inlay (pocket + plug, glue gap, start depth, boundary) | done | P1 | CAMCore/OpsVCarve/InlayOperation.swift, Panels/InlayWizardSheet.swift; VCarveInlayTests |
| `vc-inlay-boundary-options` | vcarve | Inlay plug boundary options and surface clearance | done | P2 | InlayParameters.plugBoundary/surfaceClearance; VCarveParityTests |
| `vc-vbit-engrave` | vcarve | Engraving with V-bit on open vectors (sketch carving) | done | P2 | VCarveParameters.openVectorDepth/openVectorTaper, VCarveEngraving.swift; VCarveParityTests |
| `vc-small-detail` | vcarve | Small-detail / thin-feature handling | done | P2 | Voronoi on snapped grid with sampled radii (DECISIONS scaffold/cam-vcarve); VCarveTests |
| `vc-vector-start-order` | vcarve | V-carve vector start points / selection order | done | P3 | VCarveParameters.useVectorStartPoints/useSelectionOrder, VCarveOrdering.swift; VCarveParityTests |
| `vc-photo` | vcarve | PhotoVCarve (image to V-groove engraving) | done | P3 | PhotoVCarveOperation, PhotoImageLoader, Panels/PhotoVCarveForm.swift; VCarvePhotoTests |
| `3d-import-place` | cam-3d | 3D model import, size, position and Z offset | done | P1 | Panels/ModelPlacementSheet.swift, CAMCore/Ops3D/ModelPlacement.swift; Relief3DTests |
| `3d-multiple-models` | cam-3d | Multiple models / composite model | done | P2 | Relief3DParameters.additionalModelIDs, composite ReliefHeightmap.rasterize, inspector "Combine with"; ReliefCompositeTests |
| `3d-roughing` | cam-3d | 3D roughing (Z-level, raster) with allowance | done | P1 | Ops3D/ReliefRoughing.swift + ReliefLevelRegions.swift: offset or raster (+ profile pass) per Z level; ReliefRoughingTests |
| `3d-finish-raster` | cam-3d | 3D finishing raster | done | P1 | Ops3D/ReliefFinishing.swift, DropCutter.swift; Relief3DTests |
| `3d-finish-offset` | cam-3d | 3D finishing offset / spiral strategies | done | P2 | FinishingSettings.strategy (raster/offset/spiral), Ops3D/ReliefFinishing.swift, inspector "Pattern"; ReliefFinishOffsetTests |
| `3d-boundary` | cam-3d | Limit 3D machining to boundary vectors | done | P2 | Relief3DParameters.boundaryShapeIDs, OperationForms "Use Selection as Boundary" |
| `3d-rest-machining` | cam-3d | 3D rest machining | done | P3 | FinishingSettings.restToolID, Ops3D/ReliefRest.swift, inspector "Rest after"; ReliefRestTests |
| `3d-project-2d` | cam-3d | Project 2D toolpaths onto 3D surface | done | P3 | OperationSetup.projectOntoModelID, Ops3D/ReliefProjection.swift, inspector "Project onto 3D"; ReliefProjectionTests |
| `3d-two-sided` | cam-3d | Two-sided 3D machining | done | P3 | Relief3DParameters.twoSided (side, flip, split, web), Ops3D/ReliefTwoSided.swift, inspector "Two-Sided"; ReliefTwoSidedTests. No registration-pin toolpaths |
| `3d-rotary` | cam-3d | Rotary / wrapped toolpaths (rotary job setup, wrapped and spiral toolpaths, rotary model import) | missing | P3 | Won't do: no rotary axis on the Avid and no A-axis post output (DECISIONS cam-3d) |
| `lay-nesting` | layout | True-shape nesting on sheets | done | P1 | CADCore/Layout/Nesting.swift, Panels/NestingSheet.swift; LayoutNestingTests |
| `lay-multi-sheet-nest` | layout | Nesting over multiple sheets with overflow | done | P2 | CADCore/Layout/NestSheets.swift, Nest Parts overflow + Layout > Sheet on Material; LayoutMultiSheetTests |
| `lay-tiling` | layout | Tiling large jobs | done | P3 | CAMCore/Layout/ToolpathTiling.swift, Toolpaths > Save Tiled G-code…; LayoutTilingTests, LayoutTiledExportTests |
| `lay-job-sheet` | layout | Job sheets / operator setup sheet | done | P1 | Model/JobSheet.swift (HTML), File > Export Job Sheet…; LayoutJobSheetTests |
| `lay-fixtures` | layout | Fixture / clamp helpers and keep-out zones | done | P2 | CADCore/Layout/Fixtures.swift, Panels/FixturesSheet.swift, LayoutChecks.keepOut; LayoutFixture*Tests, LayoutKeepOutTests |
| `lay-material-validation` | layout | Material-size and travel validation | done | P1 | PostCore/Validation/LayoutChecks.swift, Check Toolpaths "Material and machine"; LayoutChecksTests |
| `lay-part-labels` | layout | Part labelling (IDs/names engraved or printed on parts) | done | P3 | Model/PartLabelCommands.swift, Layout > Label Parts…, job sheet part list; LayoutPartLabel*Tests |
| `lay-production-plates` | layout | Production plate engraving: one design arrayed with text from a spreadsheet/CSV, toolpaths included | done | P3 | CADCore/Layout/ProductionPlates.swift (CSV + `{Field}` fill + grid), Model/ProductionPlateCommands.swift, Layout > Production Plates…; LayoutProductionPlate*Tests |
| `pv-3d-sim` | preview | 3D material removal simulation | done | P1 | CAMCore/Simulation/MaterialSimulator.swift, Preview/SimulationPreviewView.swift; SimMaterialSimulatorTests |
| `pv-playback` | preview | Playback controls (play/pause, scrub, speed, jump to end, reset) | done | P1 | SimulationPreviewView.swift (rewind/play/end/slider/speed); SimTimelineTests |
| `pv-show-tool` | preview | Show tool during preview | done | P2 | SimulationPreviewModel.showTool |
| `pv-preview-selected` | preview | Preview selected / visible toolpaths only | done | P2 | PreviewScope all / visible / selected |
| `pv-material-texture` | preview | Realistic shading and material textures (wood, colours, painted surface) | done | P2 | StockAppearance presets, per-vertex colours |
| `pv-measure` | preview | Measure in 3D preview | done | P3 | Preview ruler: 3D, XY and depth distances |
| `pv-time-accel` | preview | Machining time estimate with acceleration and scale factor | done | P1 | CAMCore/Simulation/MotionPlanner.swift; G-code header estimate unchanged (TODO(post)) |
| `pv-toolpath-summary` | preview | Toolpath summary (tools, times, tool-change sequence) | done | P1 | Panels/ToolChangeSummaryView.swift, Model/JobSummary.swift |
| `pv-2d-overlay` | preview | 2D toolpath overlay with rapids | done | P1 | Preview/ToolpathOverlayRenderer.swift, CanvasDrawing; RenderSmokeTests |
| `pv-save-image` | preview | Save preview image | done | P3 | Offscreen PNG of the 3D view |
| `pv-step-control` | preview | Single-step / run-to-retract simulation control | done | P3 | SimulationMoveIndex step back/forward, run to next retract |
| `pv-3d-views` | preview | Standard 3D view directions (top/front/side/iso) and orthographic mode | done | P2 | Sources/KerfApp/Preview/PreviewCamera.swift (directions + framing), StockScene.setView / isOrthographic, cube menu in SimulationPreviewView; Tests/KerfAppTests/PreviewCameraTests.swift |
| `pv-3d-toolpath-vectors` | preview | Toolpath lines and vectors shown in the 3D view (and drawing there) | partial | P2 | CAMCore/Simulation/ToolpathLines3D.swift, StockScene.showOverlay, Show menu (toolpath lines / rapids / vectors); Tests SimToolpathLines3DTests, PreviewOverlay3DTests. Drawing in the 3D view is not implemented (see DECISIONS preview-r2) |
| `ux-menus-shortcuts` | app-ux | Menus and keyboard shortcuts | done | P1 | App/KerfCommands.swift, DrawingTools.shortcut |
| `ux-preferences` | app-ux | Preferences window (default units, grid, post, snapping, colours) | done | P2 | Panels/PreferencesView.swift, Model/AppPreferences.swift; PreferencesTests |
| `ux-undo` | app-ux | Undo/redo for every document edit | done | P1 | KerfDocument.perform snapshot undo; DocumentTests |
| `ux-autosave-crash` | app-ux | Autosave and crash recovery | done | P2 | DocumentGroup autosave + Model/RecoveryStore.swift recovery copies, Panels/RecoveryPrompt.swift; RecoveryTests |
| `ux-canvas-handles` | app-ux | On-canvas resize/rotate handles and mouse node editing | done | P1 | TransformHandles.swift, CanvasNodeEvents.swift; EditingRenderTests |
| `ux-context-menus` | app-ux | Context (right-click) menus | done | P2 | Canvas/CanvasEditMenu.swift, SidebarView contextMenu |
| `ux-contextual-help` | app-ux | Contextual help and tooltips | done | P2 | Model/HelpTopics.swift, Panels/HelpView.swift (per-form ? buttons, field tooltips); HelpTopicsTests |
| `ux-onboarding` | app-ux | First-run onboarding and sample project | done | P2 | Panels/WelcomeView.swift, Model/SampleProjects.swift, bundle.sh ships samples; OnboardingTests |
| `ux-accessibility` | app-ux | Accessibility basics (VoiceOver labels, keyboard navigation, contrast) | done | P3 | Canvas/CanvasAccessibilityElements.swift, Model/CanvasAccessibility.swift (Tab selection); AccessibilityTests |
| `ux-machine-config` | app-ux | Machine configuration (bed size, post, travel limits) | done | P1 | PostCore/Model/MachineDefinition.swift, Model/MachineStore.swift, toolbar machine + post pickers; MachineConfigTests |
| `ux-async-calc` | app-ux | Background toolpath calculation with progress and cancel | done | P1 | KerfDocument.calculateAndWait, Panels/CalculationProgressView.swift |
| `ux-zoom-pan` | app-ux | Zoom/pan (fit material, fit selection, trackpad pinch) | done | P1 | CanvasViewport.swift, CanvasEvents scroll/magnify |
| `ux-split-view` | app-ux | Side-by-side 2D and 3D views | done | P3 | CenterMode.split in ContentView (⌥⌘2); AppUXRenderTests |
| `ux-gadgets` | app-ux | Gadgets / scripting API for add-on tools | done | P3 | JavaScriptCore host: Sources/KerfApp/Model/Gadgets/, Gadgets menu (GadgetPanels.swift); Tests/KerfAppTests/GadgetTests.swift. No custom gadget UI or Lua/Vectric compatibility |

## Sources

- https://www.vectric.com/products/vcarve: product and feature page, including What's New in V12.5
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/page/keyboard-shortcuts/index.html: keyboard shortcuts and the help index
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/page/whats-new/index.html: V12.5 changes
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/uiProfileMachineForm/index.html: 2D Profile toolpath
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/uiPocketMachineForm/index.html: Pocketing toolpath
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/VCarve%20Toolpath%20Creator/index.html: V-Carve toolpath
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/VCarve%20Inlay%20Toolpath/index.html: VCarve Inlay toolpath
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/ChamferStrategy/index.html: Chamfer toolpath
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/Preview%20Toolpaths/index.html: Preview Toolpaths
- https://docs.vectric.com/docs/V12.5/VCarvePro/ENU/Help/form/material-setup-flat/index.html: Material Setup
- https://community.carbide3d.com/t/awesome-vectric-vcarve-aspire-feature/12684: public forum description of production plate (variable data) arrays
