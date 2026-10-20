import CADCore
import CAMCore
import SwiftUI

/// Left sidebar: Design (layers / objects / models) and Toolpaths tabs.
struct SidebarView: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $document.sidebarTab) {
                ForEach(SidebarTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch document.sidebarTab {
            case .design: DesignSidebar(document: document)
            case .toolpaths: ToolpathsSidebar(document: document)
            }
        }
    }
}

// MARK: Design tab

struct DesignSidebar: View {
    @ObservedObject var document: KerfDocument

    private var selectionBinding: Binding<Set<UUID>> {
        Binding(get: { document.selection }, set: { new in
            // Keep the existing order for already-selected shapes, append the rest.
            let kept = document.selectedShapes.map(\.id).filter(new.contains)
            document.setSelection(kept + new.subtracting(kept).sorted { $0.uuidString < $1.uuidString })
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            LayersList(document: document)
                .frame(minHeight: 120, idealHeight: 170, maxHeight: 260)
            Divider()
            HStack {
                Text("Objects").font(.headline)
                Spacer()
                Text("\(document.document.shapes.count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.top, 8)
            List(selection: selectionBinding) {
                ForEach(document.document.layers) { layer in
                    let shapes = document.document.shapes(inLayer: layer.id)
                    if !shapes.isEmpty {
                        Section(layer.name) {
                            ForEach(shapes) { s in ShapeRow(shape: s).tag(s.id) }
                        }
                    }
                }
                if !document.document.models.isEmpty {
                    Section("3D Models") {
                        ForEach(document.document.models) { m in
                            HStack {
                                Image(systemName: "cube")
                                Text(m.name)
                                Spacer()
                                Text("\(m.mesh.triangleCount) tris").font(.caption).foregroundStyle(.secondary)
                            }
                            .contextMenu {
                                Button("Size and Position…") { document.editPlacement(of: m.id) }
                                Button("Create 3D Toolpaths…") {
                                    if var f = document.document.model(id: m.id).map({
                                        ModelPlacementForm(editing: $0, job: document.document.job, library: document.mergedLibrary)
                                    }) {
                                        f.createToolpaths = true
                                        document.sheet = .placeModel(f)
                                    }
                                }
                                Divider()
                                Button("Delete Model") {
                                    document.perform("Delete Model") { $0.document.models.removeAll { $0.id == m.id } }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Menu("Move to Layer") {
                        ForEach(document.document.layers) { l in
                            Button(l.name) { document.perform("Move to Layer") { $0.moveShapes(ids, toLayer: l.id) } }
                        }
                    }
                    Button("Duplicate") { document.setSelection(Array(ids)); document.duplicateSelection() }
                    Button("Delete") { document.perform("Delete Shapes") { $0.deleteShapes(ids) } }
                }
            }
        }
    }
}

struct ShapeRow: View {
    var shape: Shape

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            Text(shape.name.isEmpty ? "Vector" : shape.name).lineLimit(1)
            Spacer()
            if shape.isLocked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
            if !shape.isClosed { Text("open").font(.caption2).foregroundStyle(.orange) }
        }
    }

    private var icon: String {
        switch shape.origin {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .ellipse: return "oval"
        case .polygon: return "hexagon"
        case .star: return "star"
        case .text: return "textformat"
        case .imported: return "square.and.arrow.down"
        case .derived: return "square.on.square"
        case .drawn: return "scribble"
        }
    }
}

struct LayersList: View {
    @ObservedObject var document: KerfDocument
    @State private var editingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Button { document.perform("Add Layer") { $0.addLayer() } } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add layer")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            List {
                ForEach(document.document.layers) { layer in
                    LayerRow(document: document, layer: layer)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct LayerRow: View {
    @ObservedObject var document: KerfDocument
    var layer: Layer
    @State private var name = ""

    var body: some View {
        HStack(spacing: 6) {
            Button { update { $0.isVisible.toggle() } } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless).help(layer.isVisible ? "Hide layer" : "Show layer")
            Button { update { $0.isLocked.toggle() } } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.borderless).help(layer.isLocked ? "Unlock layer" : "Lock layer")
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hex: layer.colorHex) ?? .black) },
                set: { c in update { $0.colorHex = NSColor(c).hexString } }), supportsOpacity: false)
                .labelsHidden().frame(width: 28)
            TextField("Layer", text: $name, onCommit: { update { $0.name = name.isEmpty ? layer.name : name } })
                .textFieldStyle(.plain)
            Spacer()
            Text("\(document.document.shapes(inLayer: layer.id).count)").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { name = layer.name }
        .onChange(of: layer.name) { _, n in name = n }
        .contextMenu {
            Button("Select Shapes on Layer") {
                document.setSelection(document.document.shapes(inLayer: layer.id).map(\.id))
            }
            Button("Move Selection to This Layer") {
                let ids = document.selection
                document.perform("Move to Layer") { $0.moveShapes(ids, toLayer: layer.id) }
            }
            .disabled(document.selection.isEmpty)
            Divider()
            Button("Move Layer Up") { document.perform("Reorder Layers") { $0.moveLayer(layer.id, by: -1) } }
                .disabled(document.document.layers.first?.id == layer.id)
            Button("Move Layer Down") { document.perform("Reorder Layers") { $0.moveLayer(layer.id, by: 1) } }
                .disabled(document.document.layers.last?.id == layer.id)
            Divider()
            Button("Delete Layer") { document.perform("Delete Layer") { $0.deleteLayer(layer.id) } }
                .disabled(document.document.layers.count <= 1)
        }
    }

    private func update(_ change: (inout Layer) -> Void) {
        var l = layer
        change(&l)
        document.perform("Edit Layer") { $0.updateLayer(l) }
    }
}

// MARK: Toolpaths tab

struct ToolpathsSidebar: View {
    @ObservedObject var document: KerfDocument
    @EnvironmentObject var toolLibrary: ToolLibraryModel

    private var selectedOp: Binding<UUID?> {
        Binding(get: { document.selectedOperationID }, set: { document.selectedOperationID = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    ForEach(OperationFactory.menuKinds, id: \.self) { kind in
                        Button(OperationFactory.menuTitle(kind)) { document.addOperation(kind) }
                    }
                } label: {
                    Label("New Toolpath", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Toggle(isOn: $document.showToolpaths) { Image(systemName: "eye") }
                    .toggleStyle(.button).help("Show toolpaths on the canvas")
            }
            .padding(8)
            if document.project.operations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No toolpaths").font(.headline)
                    Text("Select vectors on the canvas, then choose New Toolpath.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List(selection: selectedOp) {
                    ForEach(Array(document.project.operations.enumerated()), id: \.element.id) { i, op in
                        ToolpathRow(document: document, operation: op, colorIndex: i).tag(Optional(op.id))
                            .contextMenu { rowMenu(op) }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Calculate All") { document.calculateAll() }
                    Spacer()
                    Button { document.sheet = .validation } label: { Image(systemName: "checkmark.shield") }
                        .help("Check toolpaths with the validator")
                    Button("Save All…") { document.sheet = .saveAllToolpaths }
                        .help("Save all toolpaths: one combined file or one file per toolpath/tool")
                }
                .disabled(document.project.operations.isEmpty)
                ToolChangeSummaryView(document: document)
            }
            .padding(8)
        }
    }

    @ViewBuilder private func rowMenu(_ op: AnyOperation) -> some View {
        Button("Recalculate") { document.calculate([op.id]) }
        Button("Export G-code…") { document.sheet = .exportGCode(.operation(op.id)) }
        Button("Select Vectors") { document.setSelection(op.setup.shapeIDs) }
        Divider()
        Button("Move Up") { document.perform("Reorder Toolpaths") { $0.moveOperation(op.id, by: -1) } }
        Button("Move Down") { document.perform("Reorder Toolpaths") { $0.moveOperation(op.id, by: 1) } }
        Button("Duplicate") { document.duplicateOperation(op.id) }
        Divider()
        Button("Delete", role: .destructive) { document.deleteOperation(op.id) }
    }
}

struct ToolpathRow: View {
    @ObservedObject var document: KerfDocument
    var operation: AnyOperation
    var colorIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { operation.setup.isEnabled },
                                     set: { document.setOperationEnabled(operation.id, $0) }))
                .labelsHidden().toggleStyle(.checkbox).help("Include in export")
            Button { document.toggleToolpathVisibility(operation.id) } label: {
                Image(systemName: document.hiddenToolpaths.contains(operation.id) ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless).help("Show/hide on canvas")
            Circle().fill(Color(nsColor: ToolpathColors.color(forIndex: colorIndex))).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(operation.setup.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            status
        }
        .opacity(operation.setup.isEnabled ? 1 : 0.55)
    }

    private var subtitle: String {
        let lib = document.mergedLibrary
        var tools: [String] = []
        for id in operation.referencedToolIDs {
            let t = lib.tool(id: id).map { "T\($0.number)" } ?? "missing tool"
            if !tools.contains(t) { tools.append(t) }
        }
        var s = "\(operation.kind.displayName) · \(tools.joined(separator: "+"))"
        if let r = document.results[operation.id], r.error == nil, !document.isStale(operation.id) {
            s += " · " + ToolpathCalculator.formatDuration(r.estimatedSeconds)
        }
        return s
    }

    @ViewBuilder private var status: some View {
        if document.calculating.contains(operation.id) {
            ProgressView().controlSize(.small)
        } else if let r = document.results[operation.id] {
            if let err = r.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(err)
            } else if document.isStale(operation.id) {
                Image(systemName: "arrow.clockwise.circle").foregroundStyle(.secondary).help("Needs recalculating")
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .help("Calculated · " + ToolpathCalculator.formatDuration(r.estimatedSeconds))
            }
        } else {
            Button { document.calculate([operation.id]) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.borderless).help("Calculate")
        }
    }
}
