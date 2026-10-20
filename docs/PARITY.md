# VCarve Pro parity inventory

Kerf against the public VCarve Pro 12.5 feature set, built from Vectric's public product page and online help only (see Sources). Status is judged from Kerf's code and tests: **done** = works end to end including the UI; **partial** = engine or UI only, or a subset of the options; **missing** = not implemented. Priority: **P1** = matters for typical Avid sign, part, inlay or 3D jobs; P2 = useful; P3 = niche or out of scope (for example rotary).

Totals: 163 features. 60 done, 24 partial, 79 missing. P1: 48 done, 7 partial, 8 missing.

| id | area | feature | status | priority | notes |
|---|---|---|---|---|---|
| `draw-basic-shapes` | drawing | Basic shape tools (rectangle, rounded rect, circle, ellipse, polygon, star) | done | P1 | Sources/KerfApp/Model/DrawingTools.swift, Sources/CADCore/Geometry/ShapeFactory.swift; EditingPanels numeric create; Tests/KerfAppTests/CanvasModelTests.swift |
| `draw-line-polyline` | drawing | Line / polyline tool | done | P1 | DrawingTools.polyline; CanvasEvents click-built tools |
| `draw-arc-tool` | drawing | Arc drawing tool (3-point / centre-radius) | missing | P2 | CanvasTool has no arc case (DrawingTools.swift) |
| `draw-bezier-curve` | drawing | Bézier pen and smooth curve | done | P2 | Sources/CADCore/Editing/PenPath.swift, DrawingTools.smoothCurve; EditingTests |
| `draw-freehand` | drawing | Freehand sketch tool | missing | P3 | No freehand tool in CanvasTool |
| `draw-quick-keys` | drawing | Typed quick-key entry while drawing (length/angle, W,H, radius) | partial | P2 | Inspector numeric creation + Move/Scale fields (EditingPanels.swift); no in-gesture typed entry |
| `draw-node-edit` | drawing | Node editing (move/insert/delete nodes, smooth/corner, line↔curve, break) | done | P1 | Sources/CADCore/Editing/PathNodes.swift, Canvas/CanvasNodeEvents.swift, Panels/EditingPanels.swift; EditingTests, EditingRenderTests |
| `draw-node-set-start` | drawing | Set vector start point in node edit | missing | P2 | No start-point command in PathNodes/EditingPanels |
| `draw-node-span-arc` | drawing | Convert span to arc / join and align nodes (match X/Y) | missing | P3 | PathNodes converts line↔cubic only |
| `draw-transform-handles` | drawing | On-canvas move / scale / rotate handles | done | P1 | Sources/CADCore/Editing/TransformHandles.swift, Canvas/CanvasEditingOverlay.swift; EditingRenderTests |
| `draw-numeric-transform` | drawing | Numeric move / set size / rotate / scale | done | P1 | Panels/InspectorView.swift, TransformCommands (DesignCommands.swift) |
| `draw-distort-shear` | drawing | Distort / shear / skew | missing | P3 | No shear/distort command |
| `draw-mirror` | drawing | Mirror (selection, copy, about material centre) | partial | P2 | TransformCommands.mirror about selection centre only; no mirror-copy or material-centre mode |
| `draw-align-distribute` | drawing | Align and distribute | done | P1 | DesignCommands.align/distribute/distributeSpacing; KerfCommands Align menu; EditingCommandTests |
| `draw-booleans` | drawing | Weld / subtract / intersect | done | P1 | DesignCommands.boolean, CADCore/Geometry/PathOps.swift; GeometryOpsTests |
| `draw-trim` | drawing | Interactive trim and trim-to-boundary | missing | P2 | No trim command in DesignCommands/PathOps |
| `draw-extend` | drawing | Extend vectors to boundary | missing | P3 | Not implemented |
| `draw-offset` | drawing | Offset vectors (inside/outside, round/sharp) | done | P1 | DesignCommands.offset, OffsetSheet in ExportGCodeSheet.swift; GeometryOpsTests |
| `draw-offset-open` | drawing | Offset open vectors (one side / both sides) | partial | P3 | PathOps.offsetOpen exists (CADCore) but the Offset sheet only offsets closed shapes |
| `draw-inlay-offset` | drawing | Inlay offset helper (offset for traditional end-mill inlays) | missing | P3 | Only V-carve inlay; no straight-wall inlay helper |
| `draw-fillet-chamfer` | drawing | Fillet and chamfer corners | missing | P2 | No fillet/chamfer in CADCore/Editing or DesignCommands |
| `draw-dogbone` | drawing | Dog-bone / T-bone fillets | missing | P1 | Not implemented; important for joinery/slot parts |
| `draw-smart-snap` | drawing | Smart snapping (nodes, midpoints, centres, grid) | done | P1 | Sources/CADCore/Editing/SnapEngine.swift; EditingTests |
| `draw-guides` | drawing | Guide lines and snap to guide/extension lines | missing | P2 | Rulers are drawn (CanvasDrawing.drawRulers) but no guides |
| `draw-rulers-grid` | drawing | Rulers, grid and cursor readout | done | P2 | CanvasDrawing.drawRulers, JobSetupSheet grid spacing, ContentView cursor readout |
| `draw-measure` | drawing | Measure tool (distance, angle, radius) | missing | P2 | No measure tool; only live W×H while dragging |
| `draw-array-linear` | drawing | Rectangular array copy | missing | P1 | Only Duplicate (⌘D) in EditingCommands.swift |
| `draw-array-circular` | drawing | Circular array copy | missing | P2 | Not implemented |
| `draw-copy-along` | drawing | Copy along vector | missing | P3 | Not implemented |
| `draw-copy-paste` | drawing | Copy, cut, paste, duplicate, nudge | done | P1 | ShapeClipboard (EditingCommands.swift), CanvasEvents.keyDown nudge; EditingCommandTests |
| `draw-join-close` | drawing | Join / close open vectors | done | P1 | DesignCommands.join/close, PathOps.joinOpenPaths |
| `draw-curve-fit` | drawing | Fit curves to vectors (smooth polylines into arcs/Béziers) | missing | P2 | ArcFitter exists only for toolpaths (CAMCore/Ops2D/Support/ArcFitter.swift) |
| `draw-vector-validator` | drawing | Vector validator (open, duplicate, self-intersecting, zero-length) | missing | P1 | ValidationSheet checks G-code only (Panels/ValidationSheet.swift); no design-vector checks |
| `draw-duplicate-overlap` | drawing | Find/remove duplicate and overlapping vectors | missing | P2 | Not implemented |
| `draw-layers` | drawing | Layers (visibility, lock, colour, reorder, move-to-layer) | done | P1 | Panels/SidebarView.swift layers tab, CADCore Document layers; ProjectModelTests |
| `draw-grouping` | drawing | Group / ungroup / combine / break apart | done | P1 | CADCore/Editing/Grouping.swift, DesignCommands.combine/explode |
| `draw-nested-groups` | drawing | Nested groups and deep ungroup | missing | P3 | Groups are flat (DECISIONS drawing) |
| `draw-dimensions` | drawing | Dimension objects (linear, angular, radial) | missing | P3 | Not implemented |
| `draw-text-basic` | drawing | Text in any installed font with cap-height sizing | done | P1 | CADCore/Geometry/TextOutliner.swift, DrawingTools text; TextOutlinerTests |
| `draw-text-editable` | drawing | Editable text objects (re-open to change string/font/size, alignment, spacing) | missing | P1 | Text is outlined to paths at placement; no re-edit, alignment or spacing options |
| `draw-text-autolayout` | drawing | Auto-layout text to fit a box | missing | P2 | Not implemented |
| `draw-text-on-curve` | drawing | Text on a curve / arc text / bend text | missing | P2 | Not implemented |
| `draw-single-line-fonts` | drawing | Single-stroke (engraving) fonts | missing | P2 | TextOutliner only produces closed outlines |
| `draw-kerning` | drawing | Interactive kerning / character spacing | missing | P3 | Not implemented |
| `draw-trace-bitmap` | drawing | Trace bitmap (image → vectors) | missing | P2 | No bitmap support anywhere |
| `draw-vector-texture` | drawing | Vector texture generator | missing | P3 | Texture toolpath exists but no vector texture |
| `draw-boundary-vector` | drawing | Create boundary around selection | missing | P3 | Not implemented |
| `draw-plate-maker` | drawing | Plaque / plate border generator | missing | P3 | Not implemented |
| `io-svg-import` | io | SVG import | done | P1 | CADCore/IO/SVGImporter.swift; IOSVGTests |
| `io-dxf-import` | io | DXF import | done | P1 | CADCore/IO/DXFImporter.swift; IODXFTests; samples/bracket-plate.dxf |
| `io-eps-import` | io | EPS import | done | P2 | CADCore/IO/EPSImporter.swift; IOEPSTests |
| `io-ai-pdf-import` | io | AI and PDF import (vectors, embedded images) | missing | P2 | PDF-based .ai is rejected with a message (DECISIONS cad-io); no PDF import |
| `io-svg-text` | io | SVG text and image elements on import | missing | P3 | <text>/<image> skipped with a warning (DECISIONS cad-io) |
| `io-bitmap-import` | io | Bitmap import (JPG/PNG/BMP/TIF/GIF/WebP) | missing | P2 | ImportService accepts SVG/DXF/EPS/STL only |
| `io-stl-import` | io | STL 3D model import | done | P1 | CADCore/IO/STLImporter.swift, ModelPlacementSheet; STLImporterTests |
| `io-obj-3d-import` | io | OBJ / other 3D formats import | missing | P2 | Only STL importer exists |
| `io-skp-import` | io | SketchUp import | missing | P3 | Not implemented |
| `io-vector-export` | io | Vector export (SVG, DXF) | done | P1 | CADCore/IO/SVGExporter.swift, DXFExporter.swift; KerfCommands Export Vectors |
| `io-eps-ai-export` | io | EPS / AI / PDF vector export | missing | P3 | Only SVG and DXF exporters |
| `io-project-file` | io | Native project file with versioning | done | P1 | CADCore/Persistence/KerfFile.swift; IOKerfFileTests, DocumentTests |
| `io-job-templates` | io | Job templates (saved material setup + layers + toolpaths) | missing | P2 | New documents use JobSetup.defaults only |
| `io-two-sided-setup` | io | Two-sided job setup (flip axis, per-side Z zero, both-sides view) | missing | P2 | JobSetup is single-sided (CADCore/Model/JobSetup.swift) |
| `io-material-setup` | io | Material setup (size, thickness, Z zero top/bed, XY datum, safe Z, home) | done | P1 | CADCore/Model/JobSetup.swift, Panels/JobSetupSheet.swift; MachineCoordinatesTests |
| `io-material-plunge-z` | io | Separate plunge Z (Z2) and XY datum offset | missing | P2 | JobSetup has safeZ/homeZ only; no plunge-gap or datum offset fields |
| `io-model-position` | io | Model position in material (gap above/below) | partial | P2 | ModelPlacementSheet sets model Z height and offset below top; no unified gap UI |
| `io-multiple-sheets` | io | Multiple sheets per job (different sizes/thicknesses) | missing | P2 | Single material per document |
| `io-document-variables` | io | Document variables in numeric fields | missing | P3 | Not implemented |
| `io-units-convert` | io | Unit switching inch↔mm with conversion | done | P1 | KerfApp/Model/UnitScaling.swift; ProjectModelTests |
| `io-setup-sheet` | io | Job / setup sheet (printable report) | missing | P1 | Only sidebar ToolChangeSummaryView; no printable sheet |
| `io-print` | io | Print 2D design / 3D view | missing | P3 | No print command |
| `io-post-processors` | io | Post processor selection and custom posts | done | P1 | PostCore/Profiles/BuiltInPosts.swift, PostProfileStore; PostGoldenTests, PostProfileTests |
| `io-gcode-validator` | io | G-code safety validation | done | P1 | PostCore/Validation/GCodeValidator.swift, ValidationSheet; PostValidatorTests |
| `io-save-toolpaths` | io | Save toolpaths (single, combined, per tool) | done | P1 | Panels/SaveAllToolpathsSheet.swift, Model/GCodeBatchExport.swift; AdvancedToolpathDocumentTests |
| `io-file-thumbnails` | io | File thumbnails / Quick Look | missing | P3 | Not implemented |
| `tp-profile-basic` | toolpaths-2d | Profile: inside/outside/on, climb/conventional, allowance, multi-pass | done | P1 | CAMCore/Ops2D/ProfileOperation.swift; Ops2DProfileTests; e2e sign |
| `tp-profile-open-sides` | toolpaths-2d | Profile open vectors left/right | missing | P2 | Open vectors always cut on the line (DECISIONS cam-2d) |
| `tp-profile-last-pass` | toolpaths-2d | Separate last pass (allowance, reverse direction) | partial | P1 | DepthSettings.finalPassDepth is a shallower depth pass only; no side-allowance last pass or reverse |
| `tp-pass-editor` | toolpaths-2d | Pass depth editor (exact step, custom passes, last-pass thickness) | partial | P2 | passDepth override + finalPassDepth (Parameters/CommonParameters.swift); no per-pass list |
| `tp-profile-start-point` | toolpaths-2d | Use vector start point / optimise start points | missing | P2 | Start chosen automatically (ProfileOperation) |
| `tp-profile-order` | toolpaths-2d | Profile ordering (selection order, left→right, bottom→top, grid) | partial | P2 | Greedy nearest neighbour + inner-before-outer (ChainOrdering.swift); no user ordering options |
| `tp-tabs-auto` | toolpaths-2d | Tabs: automatic count/spacing, rectangular or triangular (3D) | done | P1 | TabSettings, Ops2D/Support/PassShaping.swift; Ops2DProfileTests |
| `tp-tabs-manual` | toolpaths-2d | Tabs: on-canvas placement and editing | done | P1 | Model/TabEditor.swift, Panels/TabEditingBanner.swift; Ops2DManualTabTests |
| `tp-ramps` | toolpaths-2d | Ramps (smooth, zig-zag, spiral) by distance/angle | done | P1 | RampSettings, PassShaping.swift; Ops2DProfileTests |
| `tp-leads` | toolpaths-2d | Lead-in/out (linear, arc) and overcut | done | P1 | Ops2D/Support/Leads.swift; Ops2DProfileTests |
| `tp-sharp-corners` | toolpaths-2d | Sharp external corners (square corners) | missing | P2 | Profiles use Clipper round joins only (DECISIONS cam-2d) |
| `tp-pocket-offset-raster` | toolpaths-2d | Pocket: offset and raster with angle, islands | done | P1 | CAMCore/Ops2D/PocketOperation.swift, PocketPlanner.swift; Ops2DPocketTests |
| `tp-pocket-profile-pass` | toolpaths-2d | Pocket profile pass first/last/none | partial | P2 | Raster has a boolean final profile pass only; no "first" option |
| `tp-pocket-multi-tool` | toolpaths-2d | Pocket with multiple clearance tools (rest machining) | partial | P1 | One clearance tool + finish tool (PocketParameters.clearanceToolID) |
| `tp-pocket-ramp-allowance` | toolpaths-2d | Pocket ramp plunges and pocket allowance | done | P1 | PocketParameters.ramp/allowance; Ops2DPocketTests |
| `tp-drilling` | toolpaths-2d | Drilling with peck, dwell, retract | done | P1 | CAMCore/Ops2D/DrillOperation.swift; Ops2DDrillTests |
| `tp-drill-bank` | toolpaths-2d | Drill bank / multi-spindle drilling | missing | P3 | Avid has a single spindle; not needed |
| `tp-helical-hole` | toolpaths-2d | Helical hole milling / thread milling | missing | P2 | Only drill plunges; spiral ramp exists for profiles |
| `tp-quick-engrave` | toolpaths-2d | Quick engrave (follow vector on centreline) | partial | P1 | Achievable via Profile side=on; no dedicated engrave toolpath with V-bit width preview |
| `tp-chamfer` | toolpaths-2d | Chamfer toolpath | missing | P1 | No chamfer operation (AnyOperation.swift) |
| `tp-inlay-straight` | toolpaths-2d | Straight-wall (end-mill) inlay toolpath | missing | P3 | Only V-carve inlay |
| `tp-prism` | toolpaths-2d | Prism (raised bevel) carving | missing | P2 | No prism operation |
| `tp-moulding` | toolpaths-2d | Moulding toolpath (profile swept along rail) | missing | P3 | No moulding operation |
| `tp-fluting` | toolpaths-2d | Fluting with ramp in/out | done | P2 | CAMCore/Ops2D/FlutingOperation.swift; Ops2DFlutingTextureTests |
| `tp-texture` | toolpaths-2d | Texture toolpath | done | P3 | CAMCore/Ops2D/TextureOperation.swift; Ops2DFlutingTextureTests |
| `tp-templates` | toolpaths-2d | Toolpath templates (save/load, auto vector selection) | missing | P2 | Not implemented |
| `tp-merge` | toolpaths-2d | Merge toolpaths | missing | P3 | Group-by-tool export reduces tool changes but toolpaths are not merged |
| `tp-array-copy` | toolpaths-2d | Array copy toolpath | missing | P3 | Not implemented |
| `tp-order-visibility` | toolpaths-2d | Toolpath list: reorder, duplicate, enable, show/hide, recalc, stale status | done | P1 | Panels/SidebarView.swift ToolpathsSidebar/ToolpathRow; ProjectModelTests |
| `tp-tool-database` | toolpaths-2d | Tool database (kinds, cutting data, units, numbers) | done | P1 | CADCore/Model/ToolLibrary.swift, Panels/ToolDatabaseView.swift |
| `tp-tool-groups-materials` | toolpaths-2d | Tool groups and per-material cutting data | missing | P2 | Flat tool list, one set of cutting data per tool |
| `tp-feeds-calculator` | toolpaths-2d | Feeds and speeds calculator (chip load) | missing | P2 | Not implemented |
| `tp-tool-edit-per-toolpath` | toolpaths-2d | Per-toolpath tool parameter override | missing | P2 | Operations reference library tools by id; no local override |
| `tp-arc-output` | toolpaths-2d | Arc (G2/G3) and helical arc output | done | P2 | ArcFitter.swift; PostProfile arcOutput/helicalArcs; PostGoldenTests |
| `tp-tiling` | toolpaths-2d | Toolpath tiling for jobs larger than the bed | missing | P3 | Avid 60x96 bed is large; not implemented |
| `tp-keepout` | toolpaths-2d | Keep-out zones | missing | P2 | Not implemented |
| `vc-basic` | vcarve | V-carve (medial-axis depth from V angle) | done | P1 | CAMCore/OpsVCarve/VCarveOperation.swift, VCarveMedialAxis.swift; VCarveTests |
| `vc-flat-depth` | vcarve | Flat depth with flat-area clearance (offset/raster) | done | P1 | VCarvePocketing.swift, VCarveParameters.flatDepth/flatClearanceToolID; VCarveTests |
| `vc-multi-clearance` | vcarve | Multiple clearance tools for flat areas | partial | P2 | One flat clearance tool (VCarveParameters.flatClearanceToolID) |
| `vc-start-depth` | vcarve | Start depth (carve inside a pocket) | done | P2 | VCarveParameters.startDepth; VCarveTests |
| `vc-corner-sharpen` | vcarve | Corner sharpening | partial | P2 | V-bit traces the clamped medial axis at the flat boundary (DECISIONS cam-vcarve); no explicit lift-into-corner option |
| `vc-multi-pass` | vcarve | Multi-pass deep V-carving | done | P2 | VCarveParameters.passDepth; VCarveTests |
| `vc-inlay` | vcarve | V-carve inlay (pocket + plug, glue gap, start depth, boundary) | done | P1 | CAMCore/OpsVCarve/InlayOperation.swift, Panels/InlayWizardSheet.swift; VCarveInlayTests |
| `vc-inlay-boundary-options` | vcarve | Inlay plug boundary options and surface clearance | partial | P2 | maleBoundaryMargin (boundary offset) only; no sheet-limits or vector-offset modes, no surface clearance |
| `vc-vbit-engrave` | vcarve | Engraving with V-bit on open vectors (sketch carving) | partial | P2 | V-carve ignores open vectors with a warning; Profile on-line works at fixed depth |
| `vc-small-detail` | vcarve | Small-detail / thin-feature handling | done | P2 | Voronoi on snapped grid with sampled radii (DECISIONS scaffold/cam-vcarve); VCarveTests |
| `vc-vector-start-order` | vcarve | V-carve vector start points / selection order | missing | P3 | Chains walked to minimise lifts only |
| `vc-photo` | vcarve | PhotoVCarve (image to V-groove engraving) | missing | P3 | No bitmap support |
| `3d-import-place` | cam-3d | 3D model import, size, position and Z offset | done | P1 | Panels/ModelPlacementSheet.swift, CAMCore/Ops3D/ModelPlacement.swift; Relief3DTests |
| `3d-multiple-models` | cam-3d | Multiple models / composite model | done | P2 | Relief3DParameters.additionalModelIDs, composite ReliefHeightmap.rasterize, inspector "Combine with"; ReliefCompositeTests |
| `3d-roughing` | cam-3d | 3D roughing (Z-level, raster) with allowance | done | P1 | Ops3D/ReliefRoughing.swift + ReliefLevelRegions.swift: offset or raster (+ profile pass) per Z level; ReliefRoughingTests |
| `3d-finish-raster` | cam-3d | 3D finishing raster | done | P1 | Ops3D/ReliefFinishing.swift, DropCutter.swift; Relief3DTests |
| `3d-finish-offset` | cam-3d | 3D finishing offset / spiral strategies | done | P2 | FinishingSettings.strategy (raster/offset/spiral), Ops3D/ReliefFinishing.swift, inspector "Pattern"; ReliefFinishOffsetTests |
| `3d-boundary` | cam-3d | Limit 3D machining to boundary vectors | done | P2 | Relief3DParameters.boundaryShapeIDs, OperationForms "Use Selection as Boundary" |
| `3d-rest-machining` | cam-3d | 3D rest machining | done | P3 | FinishingSettings.restToolID, Ops3D/ReliefRest.swift, inspector "Rest after"; ReliefRestTests |
| `3d-project-2d` | cam-3d | Project 2D toolpaths onto 3D surface | done | P3 | OperationSetup.projectOntoModelID, Ops3D/ReliefProjection.swift, inspector "Project onto 3D"; ReliefProjectionTests |
| `3d-two-sided` | cam-3d | Two-sided 3D machining | done | P3 | Relief3DParameters.twoSided (side, flip, split, web), Ops3D/ReliefTwoSided.swift, inspector "Two-Sided"; ReliefTwoSidedTests. No registration-pin toolpaths |
| `3d-rotary` | cam-3d | Rotary / wrapped toolpaths | missing | P3 | Out of scope: Avid has no rotary axis |
| `lay-nesting` | layout | True-shape nesting on sheets | missing | P1 | Not implemented |
| `lay-multi-sheet-nest` | layout | Nesting over multiple sheets with overflow | missing | P2 | Not implemented |
| `lay-tiling` | layout | Tiling large jobs | missing | P3 | Not implemented |
| `lay-job-sheet` | layout | Job sheets / operator setup sheet | missing | P1 | See io-setup-sheet; only sidebar summary exists |
| `lay-fixtures` | layout | Fixture / clamp helpers and keep-out zones | missing | P2 | Not implemented |
| `lay-material-validation` | layout | Material-size and travel validation | partial | P1 | GCodeValidator checks travel span and spoilboard depth; no warning for vectors outside the material |
| `lay-part-labels` | layout | Part labelling (IDs/names engraved or printed on parts) | missing | P3 | Not implemented |
| `pv-3d-sim` | preview | 3D material removal simulation | done | P1 | CAMCore/Simulation/MaterialSimulator.swift, Preview/SimulationPreviewView.swift; SimMaterialSimulatorTests |
| `pv-playback` | preview | Playback controls (play/pause, scrub, speed, jump to end, reset) | done | P1 | SimulationPreviewView.swift (rewind/play/end/slider/speed); SimTimelineTests |
| `pv-show-tool` | preview | Show tool during preview | done | P2 | SimulationPreviewModel.showTool |
| `pv-preview-selected` | preview | Preview selected / visible toolpaths only | missing | P2 | Preview3DHost always uses all enabled calculated toolpaths |
| `pv-material-texture` | preview | Realistic shading and material textures (wood, colours, painted surface) | partial | P2 | Vertex-coloured SceneKit mesh (StockScene.swift); no material/texture choice |
| `pv-measure` | preview | Measure in 3D preview | missing | P3 | Not implemented |
| `pv-time-accel` | preview | Machining time estimate with acceleration and scale factor | partial | P1 | PostTimeEstimator/ToolpathStats: length/feed + rapids + tool changes; no acceleration or scale factor |
| `pv-toolpath-summary` | preview | Toolpath summary (tools, times, tool-change sequence) | done | P1 | Panels/ToolChangeSummaryView.swift, Model/JobSummary.swift |
| `pv-2d-overlay` | preview | 2D toolpath overlay with rapids | done | P1 | Preview/ToolpathOverlayRenderer.swift, CanvasDrawing; RenderSmokeTests |
| `pv-save-image` | preview | Save preview image | missing | P3 | Not implemented |
| `pv-step-control` | preview | Single-step / run-to-retract simulation control | missing | P3 | Continuous playback and scrubbing only |
| `ux-menus-shortcuts` | app-ux | Menus and keyboard shortcuts | done | P1 | App/KerfCommands.swift, DrawingTools.shortcut |
| `ux-preferences` | app-ux | Preferences window (default units, grid, post, snapping, colours) | missing | P2 | No Settings scene in KerfApp.swift; only kerf.groupByTool in UserDefaults |
| `ux-undo` | app-ux | Undo/redo for every document edit | done | P1 | KerfDocument.perform snapshot undo; DocumentTests |
| `ux-autosave-crash` | app-ux | Autosave and crash recovery | partial | P2 | Relies on DocumentGroup system autosave/versions; not tested, no explicit recovery |
| `ux-canvas-handles` | app-ux | On-canvas resize/rotate handles and mouse node editing | done | P1 | TransformHandles.swift, CanvasNodeEvents.swift; EditingRenderTests |
| `ux-context-menus` | app-ux | Context (right-click) menus | done | P2 | Canvas/CanvasEditMenu.swift, SidebarView contextMenu |
| `ux-contextual-help` | app-ux | Contextual help and tooltips | partial | P2 | .help tooltips on toolbar/sidebar; no help book or per-form help |
| `ux-onboarding` | app-ux | First-run onboarding and sample project | partial | P2 | samples/ and TESTING.md exist; no in-app welcome or sample opener |
| `ux-accessibility` | app-ux | Accessibility basics (VoiceOver labels, keyboard navigation, contrast) | partial | P3 | Standard SwiftUI controls are labelled; canvas has no accessibility elements |
| `ux-machine-config` | app-ux | Machine configuration (bed size, post, travel limits) | partial | P1 | Post profile carries limits (PostProfile.swift); no machine picker separate from post |
| `ux-async-calc` | app-ux | Background toolpath calculation with progress and cancel | done | P1 | KerfDocument.calculateAndWait, Panels/CalculationProgressView.swift |
| `ux-zoom-pan` | app-ux | Zoom/pan (fit material, fit selection, trackpad pinch) | done | P1 | CanvasViewport.swift, CanvasEvents scroll/magnify |
| `ux-split-view` | app-ux | Side-by-side 2D and 3D views | missing | P3 | Center pane switches between 2D and 3D only |

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
