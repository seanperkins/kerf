import CAMCore
import Foundation

/// Built-in help reference. Each form has a "?" button that opens its topic in the Help window.
/// All wording is Kerf's own.
enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted, jobSetup, machines, drawing, nodeEditing, layers, transforms
    case toolpathsOverview, profile, pocket, drilling, vcarve, inlay, fluting, texture, relief3D, tabs
    case engrave, chamfer, holeMill, prism, mergeToolpaths, straightInlay, moulding, photoVCarve
    case toolDatabase, preview, checkToolpaths, exportGCode, saveAllToolpaths, airCut
    case preferences, recovery, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .jobSetup: return "Job Setup"
        case .machines: return "Machines and Post Processors"
        case .drawing: return "Drawing Vectors"
        case .nodeEditing: return "Editing Nodes"
        case .layers: return "Layers and Groups"
        case .transforms: return "Arrange, Combine and Offset"
        case .toolpathsOverview: return "Toolpaths Overview"
        case .profile: return "Profile Toolpath"
        case .pocket: return "Pocket Toolpath"
        case .drilling: return "Drilling Toolpath"
        case .vcarve: return "V-Carve Toolpath"
        case .inlay: return "Inlay Toolpaths"
        case .fluting: return "Fluting Toolpath"
        case .texture: return "Texture Toolpath"
        case .relief3D: return "3D Relief Toolpaths"
        case .engrave: return "Quick Engrave Toolpath"
        case .chamfer: return "Chamfer Toolpath"
        case .holeMill: return "Hole Milling Toolpath"
        case .prism: return "Prism Carve Toolpath"
        case .mergeToolpaths: return "Merged Toolpaths"
        case .straightInlay: return "Straight Inlay Toolpaths"
        case .moulding: return "Moulding Toolpath"
        case .photoVCarve: return "Photo V-Carve Toolpath"
        case .tabs: return "Tabs, Ramps and Leads"
        case .toolDatabase: return "Tool Database"
        case .preview: return "2D and 3D Preview"
        case .checkToolpaths: return "Checking Toolpaths"
        case .exportGCode: return "Exporting G-code"
        case .saveAllToolpaths: return "Saving All Toolpaths"
        case .airCut: return "Running a Safe Air Cut"
        case .preferences: return "Preferences"
        case .recovery: return "Autosave and Recovery"
        case .shortcuts: return "Keyboard Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: return "star"
        case .jobSetup: return "square.dashed"
        case .machines: return "cube"
        case .drawing: return "pencil.and.outline"
        case .nodeEditing: return "point.topleft.down.curvedto.point.bottomright.up"
        case .layers: return "square.3.layers.3d"
        case .transforms: return "square.on.square"
        case .toolpathsOverview: return "list.bullet"
        case .profile: return "square"
        case .pocket: return "square.fill"
        case .drilling: return "circle.circle"
        case .vcarve: return "v.square"
        case .inlay: return "square.on.square.dashed"
        case .fluting: return "line.diagonal"
        case .texture: return "water.waves"
        case .relief3D: return "mountain.2"
        case .engrave: return "pencil.tip"
        case .chamfer: return "triangle"
        case .holeMill: return "circle.dashed"
        case .prism: return "diamond"
        case .mergeToolpaths: return "arrow.triangle.merge"
        case .straightInlay: return "square.inset.filled"
        case .moulding: return "waveform.path"
        case .photoVCarve: return "photo"
        case .tabs: return "pin"
        case .toolDatabase: return "wrench.and.screwdriver"
        case .preview: return "cube.transparent"
        case .checkToolpaths: return "checkmark.shield"
        case .exportGCode: return "square.and.arrow.up"
        case .saveAllToolpaths: return "square.and.arrow.down.on.square"
        case .airCut: return "exclamationmark.triangle"
        case .preferences: return "gearshape"
        case .recovery: return "clock.arrow.circlepath"
        case .shortcuts: return "keyboard"
        }
    }

    /// Topic for an operation's inspector form.
    static func forOperation(_ kind: OperationKind) -> HelpTopic {
        switch kind {
        case .profile: return .profile
        case .pocket: return .pocket
        case .drill: return .drilling
        case .vcarve: return .vcarve
        case .inlay: return .inlay
        case .fluting: return .fluting
        case .texture: return .texture
        case .relief3D: return .relief3D
        case .engrave: return .engrave
        case .chamfer: return .chamfer
        case .holeMill: return .holeMill
        case .prism: return .prism
        case .merge: return .mergeToolpaths
        case .straightInlay: return .straightInlay
        case .moulding: return .moulding
        case .photoVCarve: return .photoVCarve
        }
    }

    var related: [HelpTopic] {
        switch self {
        case .gettingStarted: return [.jobSetup, .drawing, .toolpathsOverview, .airCut]
        case .jobSetup: return [.machines, .airCut]
        case .machines: return [.exportGCode, .preferences]
        case .drawing: return [.nodeEditing, .transforms, .layers]
        case .nodeEditing, .layers, .transforms: return [.drawing]
        case .toolpathsOverview: return [.profile, .pocket, .vcarve, .toolDatabase]
        case .profile: return [.tabs, .toolDatabase]
        case .pocket, .drilling, .fluting, .texture: return [.toolDatabase, .preview]
        case .vcarve: return [.inlay, .toolDatabase]
        case .inlay: return [.vcarve]
        case .relief3D: return [.preview, .toolDatabase]
        case .engrave, .chamfer, .prism: return [.vcarve, .toolDatabase]
        case .holeMill: return [.drilling, .toolDatabase]
        case .mergeToolpaths: return [.toolpathsOverview]
        case .straightInlay: return [.inlay, .pocket]
        case .moulding: return [.fluting, .preview]
        case .photoVCarve: return [.vcarve, .preview]
        case .tabs: return [.profile]
        case .toolDatabase: return [.toolpathsOverview]
        case .preview: return [.checkToolpaths]
        case .checkToolpaths: return [.exportGCode, .airCut]
        case .exportGCode: return [.saveAllToolpaths, .checkToolpaths, .airCut]
        case .saveAllToolpaths: return [.exportGCode]
        case .airCut: return [.jobSetup, .exportGCode]
        case .preferences: return [.machines, .recovery]
        case .recovery: return [.preferences]
        case .shortcuts: return [.drawing]
        }
    }

    /// Markdown body (rendered with `AttributedString(markdown:)`).
    var body: String {
        switch self {
        case .gettingStarted:
            return """
            Kerf turns vector drawings into G-code for a CNC router. A typical job:

            1. **Job Setup** (⇧⌘J): material width, height and thickness, where X0 Y0 is, and whether Z zero is the material top or the spoilboard.
            2. **Pick the machine** in the toolbar. It sets the bed size and the post processors you can use.
            3. **Draw or import** vectors (File ▸ Import… for SVG, DXF, EPS or STL).
            4. **Select vectors and add a toolpath** (Toolpaths ▸ New Toolpath). Choose the tool and depths in the inspector.
            5. **Calculate** (⌘R) and look at the 2D overlay and the 3D preview.
            6. **Check** (⇧⌘K), then **Export G-code** (⇧⌘E).
            7. **Air cut first** on a new job: see "Running a Safe Air Cut".

            Help ▸ Welcome to Kerf opens a sample sign that already has toolpaths.
            """
        case .jobSetup:
            return """
            Job Setup describes the stock you clamp to the bed.

            - **Units**: changing them converts the design and every toolpath length.
            - **Material**: width (X), height (Y) and thickness (Z). The design area is the material rectangle, with (0, 0) at its lower-left corner.
            - **Z zero**: *Material surface* means you touch off on top of the stock and cuts have negative Z. *Machine bed* means you touch off on the spoilboard and the stock top is Z = thickness.
            - **XY origin**: which corner (or the centre) of the material is machine X0 Y0. Moving the origin never moves the design; it only changes the G-code numbers.
            - **Safe Z / Home**: rapid moves happen at Safe Z above the material. The program ends by going to the home position.

            Kerf warns when the material is bigger than the selected machine's bed.
            """
        case .machines:
            return """
            A **machine** is the physical router: bed size, Z travel, how far a cut may go into the spoilboard, rapid speed and spindle range. A **post processor** is the G-code dialect the controller understands.

            Pick both in the toolbar. Choosing a machine switches to one of its posts if the current one does not drive it. Validation and time estimates use the machine's limits.

            Add your own machines in Preferences ▸ Machines: duplicate a built-in machine and edit it. Custom machines are JSON files in Application Support/Kerf/machines; custom posts go in Application Support/Kerf/posts (Toolpaths ▸ Open Post Profiles Folder).
            """
        case .drawing:
            return """
            The tool palette on the left of the canvas holds the drawing tools. Single-key shortcuts: **V** select, **N** node edit, **R** rectangle, **C** circle, **E** ellipse, **L** polyline, **P** Bézier pen, **T** text.

            - Drag to draw shapes; type exact sizes in the inspector afterwards.
            - Polylines and curves: click points, double-click or press Return to finish, Esc to cancel.
            - Text uses any installed font; the size is the height of capital letters.
            - Snapping to the grid (⌘') and to object points (⇧⌘') can be paused by holding ⌘ while dragging.
            - Drag a box left→right to select shapes fully inside it, right→left to select anything it touches.
            """
        case .nodeEditing:
            return """
            Press **N** (or Design ▸ Edit Nodes) to edit the points of a vector. Drag nodes or curve handles; Shift-click to select several. The inspector can make nodes smooth or corners, convert segments between lines and curves, insert nodes and break a path.

            The first node edit turns arcs into curves and the shape becomes a plain drawn vector (it loses its rectangle/circle settings).
            """
        case .layers:
            return """
            Layers live in the Design sidebar. Hide a layer to keep its vectors out of the way, lock it to stop accidental edits, and give it a colour. New shapes go to the layer of the current selection.

            **Group** (⌘G) keeps shapes together when selecting; **Ungroup** (⇧⌘G) splits them again. **Combine Vectors** merges shapes into one; **Break Apart** splits a multi-path shape.
            """
        case .transforms:
            return """
            The Design menu aligns and distributes the selection, mirrors, rotates by 90°, joins open vectors, closes them, and runs boolean operations (union, subtract, intersect). **Offset…** grows or shrinks closed vectors.

            Drag the selection box handles to scale (Shift keeps proportions, Option scales about the centre). The round handle above the box rotates (Shift snaps to 15°).
            """
        case .toolpathsOverview:
            return """
            Select vectors, then Toolpaths ▸ New Toolpath. The toolpath appears in the Toolpaths sidebar and its settings in the inspector. Edits apply straight away; **Revert** undoes them.

            A toolpath shows as stale (faded) after its settings or the design change. Press **Calculate** or ⌘R to recalculate. Toolpaths are cut in sidebar order unless "Group by tool" is on in the export sheet. Untick "Include in export" to leave a toolpath out.
            """
        case .profile:
            return """
            A profile cuts along vectors: **Outside** to cut a part free, **Inside** to cut a hole, **On** to follow the line.

            - **Cut depth** is below the material top; use the full thickness to cut through. Passes are split by the tool's stepdown, or by **Pass depth** when set.
            - **Allowance** leaves extra material for a finishing pass (negative removes more).
            - **Climb/Conventional** sets which way the tool travels around the part.
            - Add **tabs** so through-cut parts stay attached, and **ramps** so the tool does not plunge straight down.
            """
        case .pocket:
            return """
            A pocket clears all material inside closed vectors to a depth. Vectors inside other vectors become islands that are left standing.

            - **Offset** clearing follows the outline inward; **Raster** cuts back-and-forth lines at an angle, optionally with a final profile pass.
            - A larger **clearance tool** can remove the bulk first; the finish tool then cleans the walls and corners it could not reach.
            - Kerf warns when a region is too narrow for the tool.
            """
        case .drilling:
            return """
            Drilling plunges once at the centre of each selected closed vector (or each point). Turn on **Peck drilling** to drill in steps and retract between them to clear chips; **Dwell at bottom** pauses before retracting.
            """
        case .vcarve:
            return """
            V-carving follows the centre line of shapes with a V-bit, going deeper where the shape is wider, so letters get crisp corners.

            - **Flat depth** limits the depth; wider areas are then cleared flat, optionally with a separate **flat area tool** (an end mill).
            - **Max pass depth** splits deep carves into several passes.
            - Only closed vectors are carved; text counters (the holes in letters) are respected.
            """
        case .inlay:
            return """
            An inlay is a V-carved **pocket** in one board and a matching **plug** cut from another board, glued in and planed flush.

            New Toolpath ▸ Inlay opens a wizard that creates both toolpaths. The plug is created disabled because it must be cut from its own board: export it as a separate file. **Glue gap** sets the space left at the bottom for glue.
            """
        case .engrave:
            return """
            Quick Engrave runs the tool straight along the selected vectors at one depth, with no offset to either side. Use it for single-line text, score lines and layout marks.

            Set the **depth** and the cut direction. Deep engraves are split into passes by the tool's stepdown.
            """
        case .chamfer:
            return """
            Chamfer runs a V-bit along the edges of a part so the side of the cone cuts a bevel.

            - **Side** says which side of a closed vector is the part; the bevel is cut into the part edge.
            - Give the **width** of the bevel on the top face, or a **depth**; the other follows from the bit angle.
            - **Tip clearance** keeps the bit's point off the wall by running it slightly into the waste.
            """
        case .holeMill:
            return """
            Hole Milling cuts round holes with an end mill smaller than the hole, centred on each selected circle.

            - **Helical bore** spirals down at the hole radius, then makes one flat lap at the bottom. **Helix pitch** is the depth per turn.
            - **Thread milling** cuts an internal thread with a thread mill in a pilot hole. Set the thread pitch and hand.
            - Leave the diameter empty to use each circle's own size.
            """
        case .prism:
            return """
            Prism Carve runs a V-bit round each shape deep enough that the two sloping walls meet in a sharp ridge down the middle, so letters and shapes stand out as bevelled prisms.

            Set a **max depth** to stop wide shapes going too deep; they then keep a flat top.
            """
        case .mergeToolpaths:
            return """
            Merging combines several toolpaths into one entry that is cut in the listed order. It keeps the sidebar short and keeps related cuts together in the G-code.

            Choose **Split Into Separate Toolpaths** in the inspector to get the original toolpaths back.
            """
        case .straightInlay:
            return """
            A straight inlay cuts a pocket in one board and a matching plug in another, both with an end mill. Corners are rounded to what the tool can cut, so the plug fits the pocket.

            - **Clearance** is the gap all round between plug and pocket wall.
            - Make the **plug depth** a little more than the pocket depth.
            - Turn on **Mirror plug** when the plug is glued in face down.
            """
        case .moulding:
            return """
            Moulding sweeps a cross-section shape along one or more rail vectors to carve a profile, such as a picture-frame edge.

            Select the rails, then the cross-section last. The section's left edge sits on the rail and its top is the material surface. **Rough in levels first** removes material in flat levels before the finishing passes. Curved rails are carved approximately.
            """
        case .photoVCarve:
            return """
            Photo V-Carve engraves a picture as rows of parallel V-grooves. Darker parts of the image get wider, deeper grooves; black areas are carved as wide as the line spacing.

            Choose the image, set its width and position (or **Fit to Material**), the groove **angle** and **line spacing**. **Invert** carves the light areas instead, for a light fill in dark wood.
            """
        case .fluting:
            return """
            Fluting runs a ball-nose or V-bit along open or closed vectors and ramps the depth at the start, the end or both, giving tapered decorative grooves. **Ramp length** is a percentage of each vector's length.
            """
        case .texture:
            return """
            Texture covers the selected area with short random scoops, like a hand-tooled surface. Spacing, stroke length, angle and variation shape the pattern; the **seed** makes it repeatable.
            """
        case .relief3D:
            return """
            Import an STL model (File ▸ Import…) to place it on the job and create **Roughing** and **Finishing** toolpaths.

            - Roughing removes most material in flat layers with an end mill, leaving an **allowance**.
            - Finishing follows the surface with a ball-nose in raster lines; a smaller **stepover** gives a smoother finish but takes longer.
            - **Resolution** is the size of the height grid used for calculation.
            """
        case .tabs:
            return """
            **Tabs** are small bridges left at the bottom of a through cut so the part does not move. Set their length and thickness; choose automatic spacing or Placement: Manual and **Edit on Canvas** to click where they go (drag to slide, Option-click to delete).

            **Ramps** enter the material gradually (smooth, zigzag or spiral) instead of plunging. **Leads** start and finish the cut just outside the part to avoid marks; **Overcut** goes past the start point to clean the seam.
            """
        case .toolDatabase:
            return """
            Toolpaths ▸ Tool Database (⇧⌘T) lists your cutters. Each tool has a type, diameter, angle (V-bits), stepdown, stepover, spindle speed, feed and plunge rates. Tools are shared by all jobs and saved in Application Support/Kerf/tools.json; jobs also keep a copy of the tools they use.
            """
        case .preview:
            return """
            The **2D** view draws calculated toolpaths over the design: solid lines are cuts, dashed red lines are rapid moves. Toolpaths ▸ Show Toolpaths (⌥⌘T) hides them.

            The **3D** view simulates cutting the material. Press Play, scrub the timeline or change the speed. **2D | 3D** shows both side by side.
            """
        case .checkToolpaths:
            return """
            Toolpaths ▸ Check Toolpaths… (⇧⌘K) checks every enabled toolpath and the combined program against the machine: travel limits, cuts into the spoilboard, rapids below the material, spindle speed range, and missing feeds. **Errors** must be fixed or explicitly accepted; **warnings** are worth a look.
            """
        case .exportGCode:
            return """
            File ▸ Export G-code… (⇧⌘E) writes one program. Choose all enabled toolpaths or a single one, and the post processor. **Group by tool** reorders toolpaths to reduce tool changes when that is safe (profiles that cut parts free stay last).

            The validator runs on the output; if it reports errors you must confirm before saving.
            """
        case .saveAllToolpaths:
            return """
            Toolpaths ▸ Save All Toolpaths… (⌥⌘S) writes several programs at once: one file grouped by tool, one file in list order, one file per toolpath, or one file per tool. Multi-file modes ask for a folder; names get a run-order prefix.
            """
        case .airCut:
            return """
            Before cutting a new job for real:

            1. Zero X and Y as set in Job Setup.
            2. Zero Z **1–2 inches above** the material (or spoilboard), so every move happens in the air.
            3. Leave the spindle off and run the program at reduced feed, watching tool changes, rapids and the final home move.
            4. Re-zero Z properly and run the real cut.

            Always wear eye and hearing protection and keep a hand near the E-stop.
            """
        case .preferences:
            return """
            Kerf ▸ Settings… (⌘,) sets the defaults for **new** documents (units, grid spacing, machine, post, snapping), the canvas colours, how often recovery copies are saved, and whether the Welcome window opens at launch. Open documents keep their own settings.
            """
        case .recovery:
            return """
            Kerf saves documents through macOS (File ▸ Save, Revert To, and Browse All Versions). In addition, every open document with unsaved changes is copied to a recovery folder on a timer (Preferences ▸ General).

            If Kerf quits unexpectedly, the next launch offers to recover those documents; they open as new, untitled windows that you then save. File ▸ Recover Unsaved Work… shows them again. Recovered and discarded copies are kept in Recovery/Archive.
            """
        case .shortcuts:
            return """
            - **Canvas tools**: V select · N nodes · R rectangle · C circle · E ellipse · L polyline · P pen · T text
            - **View**: ⌘0 zoom to material · ⌘2 zoom to selection · ⌘= / ⌘- zoom · ⌥⌘1 2D · ⌥⌘2 2D and 3D · ⌥⌘3 3D · ⌥⌘T toolpaths
            - **Design**: ⇧⌘J Job Setup · ⌘D duplicate · ⌘G / ⇧⌘G group / ungroup · ⌘[ / ⌘] rotate 90° · ⌘' snap to grid · ⇧⌘' snap to objects
            - **Canvas keyboard**: Tab / ⇧Tab select the next / previous shape (⌃Tab leaves the canvas) · arrow keys nudge (⇧ for ×10) · Delete removes · Esc clears
            - **Toolpaths**: ⌘R calculate all · ⇧⌘K check · ⇧⌘E export · ⌥⌘S save all · ⇧⌘T tool database
            - **Help**: ⌘? Kerf Help
            """
        }
    }

    /// Topics whose title or body contain every word of `query` (case-insensitive).
    static func search(_ query: String) -> [HelpTopic] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return allCases }
        return allCases.filter { t in
            let text = (t.title + " " + t.body).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
}

/// Tooltips for form fields, keyed by the field label (used when a field has no explicit help).
enum FieldHelp {
    static let texts: [String: String] = [
        "Start depth": "Depth below the material top where cutting starts",
        "Cut depth": "Final depth below the material top",
        "Pass depth": "Maximum depth of each pass (off = the tool's stepdown)",
        "Max pass depth": "Split the carve into passes no deeper than this (off = one pass)",
        "Final pass": "Thin last pass for a cleaner floor (0 = none)",
        "Ramp length": "Distance over which the tool descends into the material",
        "Max angle": "Steepest allowed ramp angle",
        "Raster angle": "Direction of raster lines (0° = along X)",
        "Allowance": "Material left on the part for a later finishing pass (negative removes more)",
        "Length": "Length of each tab along the cut",
        "Thickness": "Height of each tab above the bottom of the cut",
        "Spacing": "Distance between tabs or strokes",
        "Lead radius": "Radius of the arc that leads into and out of the cut",
        "Lead length": "Length of the straight lead into and out of the cut",
        "Overcut": "Distance cut past the start point to clean the seam",
        "Peck depth": "Depth added by each peck",
        "Retract height": "Height above the material the drill lifts to between pecks",
        "Dwell at bottom": "Pause at the bottom of each hole before retracting",
        "Flat depth": "Deepest the V-bit goes; wider areas are cleared flat at this depth",
        "Pocket depth": "Depth of the inlay pocket in the receiving board",
        "Plug start depth": "How far below the plug board's top the plug's carve starts",
        "Glue gap": "Space left between the plug and the pocket floor for glue",
        "Plug boundary margin": "Extra material cleared around the plug outline",
        "Max depth": "Deepest point of each texture stroke",
        "Min stroke": "Shortest texture stroke",
        "Max stroke": "Longest texture stroke",
        "Angle": "Direction of the strokes (0° = along X)",
        "Variation": "How much stroke length and depth vary randomly",
        "Resolution": "Size of the height grid cell used to calculate 3D toolpaths",
        "Stepover": "Distance between neighbouring passes",
        "Width (X)": "Material size along the machine's X axis",
        "Height (Y)": "Material size along the machine's Y axis",
        "Thickness (Z)": "Material thickness",
        "Safe Z": "Height above the material for rapid moves",
        "Home Z": "Height above the material at the end of the program",
        "Grid spacing": "Distance between grid lines used for snapping",
        "Rapid rate": "Rapid traverse speed, used for time estimates",
    ]

    static func text(for label: String) -> String? { texts[label] }
}
