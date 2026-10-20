import AppKit
import CADCore
import CAMCore
import SwiftUI

/// Right-hand inspector: drawing-tool options, toolpath parameters, selection properties or
/// the job summary, depending on context.
struct InspectorView: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if document.activeTool == .nodeEdit {
                    NodeInspector(document: document)
                } else if document.activeTool != .select {
                    DrawingOptionsView(document: document)
                } else if document.sidebarTab == .toolpaths, let op = document.operation(document.selectedOperationID) {
                    OperationEditor(document: document, original: op).id(op.id)
                } else if !document.selection.isEmpty {
                    ShapeInspector(document: document)
                } else {
                    JobSummaryView(document: document)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Drawing tool options

struct DrawingOptionsView: View {
    @ObservedObject var document: KerfDocument
    @State private var fonts: [String] = []

    var body: some View {
        let units = document.units
        InspectorSection(title: document.activeTool.title) {
            switch document.activeTool {
            case .rectangle, .ellipse:
                Text("Drag a box. Hold Shift for a square/circle.").font(.callout).foregroundStyle(.secondary)
            case .roundedRectangle:
                LengthField("Corner radius", value: $document.drawingOptions.cornerRadius, units: units)
                Text("Drag a box. Hold Shift for a square.").font(.callout).foregroundStyle(.secondary)
            case .circle:
                Text("Drag from the centre outwards.").font(.callout).foregroundStyle(.secondary)
            case .polygon:
                IntField("Sides", value: $document.drawingOptions.polygonSides, range: 3...64)
                Text("Drag from the centre to a corner.").font(.callout).foregroundStyle(.secondary)
            case .star:
                IntField("Points", value: $document.drawingOptions.starPoints, range: 2...64)
                NumberField("Inner ratio", value: $document.drawingOptions.starInnerRatio)
                Text("Drag from the centre to a point.").font(.callout).foregroundStyle(.secondary)
            case .polyline:
                Text("Click to add points. Click the first point to close, double-click or Return to finish, Esc to cancel.")
                    .font(.callout).foregroundStyle(.secondary)
            case .curve:
                Text("Click points for a smooth Bézier curve. Click the first point to close; double-click or Return to finish.")
                    .font(.callout).foregroundStyle(.secondary)
            case .pen:
                Text("Click for a corner node, click-drag for a smooth node. Click the first node to close; double-click or Return to finish; Delete removes the last node.")
                    .font(.callout).foregroundStyle(.secondary)
            case .arc:
                ArcToolOptions(document: document)
            case .trim:
                TrimToolOptions(document: document)
            case .measure:
                MeasureToolOptions(document: document)
            case .dimension:
                DimensionToolOptions(document: document)
            case .freehand:
                Text("Drag to sketch. The stroke is smoothed into curves when you let go; end near the start to close it.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .text:
                TextField("Text", text: $document.drawingOptions.text, axis: .vertical).lineLimit(1...6)
                Picker("Font", selection: $document.drawingOptions.fontName) {
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                }
                LengthField("Height", value: $document.drawingOptions.fontSize, units: units)
                TextLayoutFields(alignment: $document.drawingOptions.textAlignment,
                                 lineSpacing: $document.drawingOptions.lineSpacing,
                                 letterSpacing: $document.drawingOptions.letterSpacing, units: units)
                Text("Click on the canvas to place the text. The click is the start, centre or end of the first baseline, following the justification. Text stays editable until converted to curves.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .select, .nodeEdit:
                EmptyView()
            }
            QuickEntryHelp(tool: document.activeTool)
            Toggle("Snap to grid", isOn: $document.snapToGrid)
            Toggle("Snap to objects", isOn: $document.snapToObjects)
            Button("Done") { document.activeTool = .select }
        }
        .onAppear {
            let fromCore = TextOutliner.availableFontNames()
            fonts = [StrokeFont.name] + (fromCore.isEmpty ? NSFontManager.shared.availableFontFamilies : fromCore)
            if !fonts.contains(document.drawingOptions.fontName), let f = fonts.first { document.drawingOptions.fontName = f }
        }
        if document.activeTool.isDragShape {
            Divider()
            ExactShapeSection(document: document)
        }
    }
}

// MARK: Selection properties

struct ShapeInspector: View {
    @ObservedObject var document: KerfDocument
    @State private var box = Rect2(x: 0, y: 0, width: 1, height: 1)
    @State private var keepAspect = true
    @State private var rotation = 90.0
    @State private var name = ""

    private var ids: Set<UUID> { document.selection }
    private var bounds: Rect2 { document.project.bounds(of: ids) }

    var body: some View {
        let units = document.units
        let shapes = document.selectedShapes
        InspectorSection(title: shapes.count == 1 ? "Shape" : "\(shapes.count) Shapes") {
            if shapes.count == 1, let s = shapes.first {
                TextField("Name", text: $name, onCommit: {
                    var c = s; c.name = name
                    document.perform("Rename") { $0.document.replace(c) }
                })
                Text(describe(s)).font(.caption).foregroundStyle(.secondary)
                Toggle("Locked", isOn: Binding(get: { s.isLocked }, set: { v in
                    var c = s; c.isLocked = v
                    document.perform(v ? "Lock" : "Unlock") { $0.document.replace(c) }
                }))
            }
            Picker("Layer", selection: Binding(get: { shapes.first?.layerID ?? document.document.defaultLayerID },
                                               set: { l in document.perform("Move to Layer") { $0.moveShapes(ids, toLayer: l) } })) {
                ForEach(document.document.layers) { Text($0.name).tag($0.id) }
            }
        }
        if shapes.count == 1, let s = shapes.first, s.text != nil {
            Divider()
            TextEditSection(document: document, shape: s).id(s.id)
        }
        Divider()
        InspectorSection(title: "Position & Size") {
            LengthField("X (left)", value: $box.min.x, units: units)
            LengthField("Y (bottom)", value: $box.min.y, units: units)
            LengthField("Width", value: Binding(get: { box.width }, set: { setSize(w: $0, h: nil) }), units: units)
            LengthField("Height", value: Binding(get: { box.height }, set: { setSize(w: nil, h: $0) }), units: units)
            Toggle("Keep proportions", isOn: $keepAspect)
            HStack {
                Button("Apply") {
                    let target = box
                    document.perform("Resize") { TransformCommands.fit(ids, to: target, keepAspect: false, in: &$0) }
                }
                Button("Revert") { box = bounds }
            }
        }
        .onAppear { box = bounds; name = shapes.first?.name ?? "" }
        .onChange(of: document.project) { _, _ in box = bounds; name = document.selectedShapes.first?.name ?? "" }
        .onChange(of: document.selection) { _, _ in box = bounds; name = document.selectedShapes.first?.name ?? "" }
        Divider()
        InspectorSection(title: "Transform") {
            HStack {
                NumberField("Rotate", value: $rotation, unit: "°")
                Button("Apply") { let r = rotation; document.perform("Rotate") { TransformCommands.rotate(ids, degrees: r, in: &$0) } }
            }
            MoveScaleFields(document: document)
            HStack {
                Button("Mirror ↔") { document.perform("Mirror") { TransformCommands.mirror(ids, horizontally: true, in: &$0) } }
                Button("Mirror ↕") { document.perform("Mirror") { TransformCommands.mirror(ids, horizontally: false, in: &$0) } }
            }
        }
        Divider()
        InspectorSection(title: "Arrange") {
            AlignButtons(document: document)
        }
        Divider()
        InspectorSection(title: "Edit Vectors") {
            EditVectorButtons(document: document)
        }
        Divider()
        InspectorSection(title: "Toolpath from Selection") {
            Menu("New Toolpath") {
                ForEach(OperationFactory.menuKinds, id: \.self) { k in Button(k.displayName) { document.addOperation(k) } }
            }
        }
    }

    private func setSize(w: Double?, h: Double?) {
        let b = box
        var nw = w ?? b.width, nh = h ?? b.height
        if keepAspect, b.width > 0, b.height > 0 {
            if let w { nh = b.height * w / b.width } else if let h { nw = b.width * h / b.height }
        }
        box = Rect2(x: b.min.x, y: b.min.y, width: max(nw, 1e-6), height: max(nh, 1e-6))
    }

    private func describe(_ s: Shape) -> String {
        let u = document.units.abbreviation
        func f(_ v: Double) -> String { RulerTicks.label(v) }
        switch s.origin {
        case .rectangle(let w, let h, let r): return "Rectangle \(f(w)) × \(f(h)) \(u)" + (r > 0 ? ", radius \(f(r))" : "")
        case .circle(let r): return "Circle, radius \(f(r)) \(u)"
        case .ellipse(let rx, let ry): return "Ellipse \(f(2 * rx)) × \(f(2 * ry)) \(u)"
        case .polygon(let n, let r): return "\(n)-sided polygon, radius \(f(r)) \(u)"
        case .star(let n, let ro, _): return "\(n)-point star, radius \(f(ro)) \(u)"
        case .text(let t, let font, let size): return "Text “\(t)” · \(font) \(f(size)) \(u)"
        case .imported(let fmt): return "Imported from \(fmt.uppercased())"
        case .derived(let op): return "Result of \(op)"
        case .drawn: return s.isClosed ? "Closed vector" : "Open vector"
        }
    }
}

struct AlignButtons: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        let ids = document.selection
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                btn("align.horizontal.left", .left); btn("align.horizontal.center", .centerX); btn("align.horizontal.right", .right)
            }
            GridRow {
                btn("align.vertical.bottom", .bottom); btn("align.vertical.center", .centerY); btn("align.vertical.top", .top)
            }
        }
        HStack {
            Button("Centre on Material") { document.perform("Align") { DesignCommands.align(ids, mode: .materialCenter, in: &$0) } }
        }
        HStack {
            Button("Distribute ↔") { document.perform("Distribute") { DesignCommands.distribute(ids, horizontally: true, in: &$0) } }
                .disabled(ids.count < 3)
            Button("Distribute ↕") { document.perform("Distribute") { DesignCommands.distribute(ids, horizontally: false, in: &$0) } }
                .disabled(ids.count < 3)
        }
        HStack {
            Button("Space ↔") { document.perform("Distribute") { DesignCommands.distributeSpacing(ids, horizontally: true, in: &$0) } }
                .disabled(ids.count < 3).help("Equal gaps between shapes, horizontally")
            Button("Space ↕") { document.perform("Distribute") { DesignCommands.distributeSpacing(ids, horizontally: false, in: &$0) } }
                .disabled(ids.count < 3).help("Equal gaps between shapes, vertically")
        }
    }

    private func btn(_ icon: String, _ mode: AlignMode) -> some View {
        let ids = document.selection
        return Button { document.perform("Align") { DesignCommands.align(ids, mode: mode, in: &$0) } } label: {
            Image(systemName: icon).frame(width: 24)
        }
        .help(mode.title)
        .disabled(ids.count < 2)
    }
}

struct EditVectorButtons: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        let order = document.selectedShapes.map(\.id)
        let tol = document.units == .inch ? 0.001 : 0.025
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ForEach(BooleanMode.allCases) { mode in
                    Button(mode.title) {
                        var newID: UUID?
                        document.perform(mode.title) { newID = DesignCommands.boolean(mode, ids: order, in: &$0) }
                        if let id = newID { document.setSelection([id]) }
                    }
                    .disabled(order.count < 2)
                }
            }
            HStack {
                Button("Offset…") { document.sheet = .offset }
                Button("Join") {
                    var newID: UUID?
                    document.perform("Join") { newID = DesignCommands.join(order, tolerance: tol, in: &$0) }
                    if let id = newID { document.setSelection([id]) }
                }
                Button("Close") { let ids = Set(order); document.perform("Close Vectors") { DesignCommands.close(ids, in: &$0) } }
            }
            HStack {
                Button("Group") { document.groupSelection() }
                    .disabled(order.count < 2)
                Button("Ungroup") { document.ungroupSelection() }
                    .disabled(!document.selectedShapes.contains { $0.groupID != nil })
                Button("Edit Nodes") { document.activeTool = .nodeEdit }
            }
            HStack {
                Button("Combine") {
                    var newID: UUID?
                    document.perform("Combine") { newID = DesignCommands.combine(order, in: &$0) }
                    if let id = newID { document.setSelection([id]) }
                }
                .disabled(order.count < 2).help("Merge the selected vectors into one multi-path shape")
                Button("Break Apart") {
                    var ids: [UUID] = []
                    let sel = Set(order)
                    document.perform("Break Apart") { ids = DesignCommands.explode(sel, in: &$0) }
                    if !ids.isEmpty { document.setSelection(ids) }
                }
                .help("Split multi-path shapes into one shape per path")
                Button("Delete", role: .destructive) { document.deleteSelection() }
            }
        }
    }
}

// MARK: Job summary (nothing selected)

struct JobSummaryView: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        let j = document.document.job
        let u = document.units.abbreviation
        InspectorSection(title: "Job") {
            LabeledContent("Material", value: GCodeExporter.materialDescription(document.document))
            LabeledContent("XY origin", value: j.xyOrigin.displayName)
            LabeledContent("Z zero", value: j.zZero.displayName)
            LabeledContent("Safe Z", value: "\(RulerTicks.label(j.safeZ)) \(u)")
            LabeledContent("Home", value: "X\(RulerTicks.label(j.home.x)) Y\(RulerTicks.label(j.home.y)) Z\(RulerTicks.label(j.homeZ)) \(u)")
            LabeledContent("Machine", value: document.postProfile.name)
            Button("Job Setup…") { document.sheet = .jobSetup }
        }
        Divider()
        InspectorSection(title: "Getting Started") {
            Text("1. Set the material size and zero in Job Setup.\n2. Draw shapes with the palette or File › Import.\n3. Select vectors and add a toolpath.\n4. Calculate, check the preview, then Export G-code.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
