import CADCore
import CAMCore
import SwiftUI

/// Edits a draft copy of an operation; "Save" commits it (one undo step), "Calculate" also
/// generates the toolpath.
struct OperationEditor: View {
    @ObservedObject var document: KerfDocument
    let original: AnyOperation
    @State private var draft: AnyOperation

    init(document: KerfDocument, original: AnyOperation) {
        self.document = document
        self.original = original
        _draft = State(initialValue: original)
    }

    private var units: LengthUnit { document.units }
    private var library: ToolLibrary { document.mergedLibrary }

    var body: some View {
        InspectorSection(title: draft.kind.displayName + " Toolpath") {
            TextField("Name", text: setupBinding(\.name))
            Toggle("Include in export", isOn: setupBinding(\.isEnabled))
            ToolPicker(title: OperationFactory.primaryToolTitle(draft.kind), toolID: setupBinding(\.toolID), library: library,
                       preferred: OperationFactory.preferredToolKinds(for: draft.kind))
            if draft.kind != .relief3D {
                vectorsRow
            }
        }
        Divider()
        parameterForm
        Divider()
        resultView
        HStack {
            Button("Calculate") { save(); document.calculate([draft.id]) }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            Button("Save") { save() }.disabled(draft == original)
            Button("Revert") { draft = original }.disabled(draft == original)
            Spacer()
            Button(role: .destructive) { document.deleteOperation(draft.id) } label: { Image(systemName: "trash") }
                .help("Delete toolpath")
        }
        .onChange(of: original) { _, new in draft = new }
    }

    private var vectorsRow: some View {
        let count = draft.setup.shapeIDs.count
        let selCount = document.selection.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(count == 0 ? "No vectors selected" : "\(count) vector\(count == 1 ? "" : "s")")
                .foregroundStyle(count == 0 ? .orange : .primary)
            HStack {
                Button("Use Current Selection (\(selCount))") {
                    var s = draft.editableSetup
                    s.shapeIDs = document.selectedShapes.map(\.id)
                    draft.editableSetup = s
                }
                .disabled(selCount == 0)
                Button("Show") { document.setSelection(draft.setup.shapeIDs) }.disabled(count == 0)
            }
        }
    }

    @ViewBuilder private var parameterForm: some View {
        switch draft {
        case .profile(let o):
            ProfileForm(params: paramsBinding(o.params) { .profile(ProfileOperation(setup: draft.setup, params: $0)) }, units: units,
                        shapes: document.document.shapes(ids: draft.setup.shapeIDs), isEditingTabs: editingTabsBinding)
        case .pocket(let o):
            PocketForm(params: paramsBinding(o.params) { .pocket(PocketOperation(setup: draft.setup, params: $0)) },
                       units: units, library: library, finishToolID: draft.setup.toolID)
        case .drill(let o):
            DrillForm(params: paramsBinding(o.params) { .drill(DrillOperation(setup: draft.setup, params: $0)) }, units: units)
        case .vcarve(let o):
            VCarveForm(params: paramsBinding(o.params) { .vcarve(VCarveOperation(setup: draft.setup, params: $0)) },
                       units: units, library: library)
        case .inlay(let o):
            InlayForm(params: paramsBinding(o.params) { .inlay(InlayOperation(setup: draft.setup, params: $0)) },
                      units: units, library: library)
        case .fluting(let o):
            FlutingForm(params: paramsBinding(o.params) { .fluting(FlutingOperation(setup: draft.setup, params: $0)) }, units: units)
        case .texture(let o):
            TextureForm(params: paramsBinding(o.params) { .texture(TextureOperation(setup: draft.setup, params: $0)) }, units: units)
        case .relief3D(let o):
            Relief3DForm(params: paramsBinding(o.params) { .relief3D(Relief3DOperation(setup: draft.setup, params: $0)) },
                         units: units, library: library, models: document.document.models,
                         selection: document.selectedShapes.map(\.id))
        }
    }

    @ViewBuilder private var resultView: some View {
        if document.calculating.contains(draft.id) {
            HStack { ProgressView().controlSize(.small); Text("Calculating…") }
        } else if let r = document.results[draft.id] {
            VStack(alignment: .leading, spacing: 4) {
                if let e = r.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let moves = r.toolpaths.reduce(0) { $0 + $1.moves.count }
                    Label("\(r.toolpaths.count) toolpath\(r.toolpaths.count == 1 ? "" : "s"), \(moves) moves",
                          systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Estimated time: " + ToolpathCalculator.formatDuration(r.estimatedSeconds))
                        .font(.caption).foregroundStyle(.secondary)
                    if r.toolpaths.count > 1 {
                        ForEach(r.toolpaths) { tp in
                            let secs = MachiningTimeEstimator.estimate([tp], rapidRate: document.rapidRateInDocumentUnits)
                            Text("• \(tp.name): T\(tp.tool.number), \(ToolpathCalculator.formatDuration(secs))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let changes = max(0, JobSummary.sequence(of: r.toolpaths).count - 1)
                        if changes > 0 {
                            Text("\(changes) tool change\(changes == 1 ? "" : "s") within this toolpath")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(r.toolpaths.flatMap { $0.metadata.sorted { $0.key < $1.key } }, id: \.key) { kv in
                        Text("\(kv.key): \(kv.value)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if document.isStale(draft.id) {
                    Text("Parameters or design changed — recalculate.").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Bindings

    /// On-canvas tab editing for this (Profile) operation. Turning it on saves the draft first so
    /// canvas edits start from what the form shows.
    private var editingTabsBinding: Binding<Bool> {
        Binding(get: { document.tabEditingOperationID == draft.id }, set: { on in
            if on {
                save()
                document.centerMode = .design2D
                document.tabEditingOperationID = draft.id
            } else if document.tabEditingOperationID == draft.id {
                document.tabEditingOperationID = nil
            }
        })
    }

    private func setupBinding<T>(_ kp: WritableKeyPath<OperationSetup, T>) -> Binding<T> {
        Binding(get: { draft.setup[keyPath: kp] }, set: { v in
            var s = draft.editableSetup
            s[keyPath: kp] = v
            draft.editableSetup = s
        })
    }

    private func paramsBinding<P>(_ current: P, _ wrap: @escaping (P) -> AnyOperation) -> Binding<P> {
        Binding(get: { current }, set: { draft = wrap($0) })
    }

    private func save() {
        if draft != original { document.updateOperation(draft) }
    }
}

/// Tool chooser: preferred kinds first, plus a "Tool Database…" shortcut.
struct ToolPicker: View {
    var title: String
    @Binding var toolID: UUID
    var library: ToolLibrary
    var preferred: [ToolKind]
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let sorted = library.tools.sorted { a, b in
            let ia = preferred.firstIndex(of: a.kind) ?? 99, ib = preferred.firstIndex(of: b.kind) ?? 99
            return ia != ib ? ia < ib : a.number < b.number
        }
        HStack {
            Picker(title, selection: $toolID) {
                if library.tool(id: toolID) == nil { Text("Missing tool").tag(toolID) }
                ForEach(sorted) { t in Text("T\(t.number) · \(t.name)").tag(t.id) }
            }
            Button { openWindow(id: ToolDatabaseView.windowID) } label: { Image(systemName: "wrench.and.screwdriver") }
                .buttonStyle(.borderless).help("Tool Database")
        }
        if let t = library.tool(id: toolID) {
            Text(toolSummary(t)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func toolSummary(_ t: Tool) -> String {
        let u = t.units.abbreviation
        var s = "⌀\(RulerTicks.label(t.diameter)) \(u) · \(t.kind.displayName)"
        if let a = t.angle { s += " \(RulerTicks.label(a))°" }
        s += " · \(Int(t.spindleRPM)) RPM · F\(RulerTicks.label(t.feedRate)) / P\(RulerTicks.label(t.plungeRate)) \(t.units.feedUnit)"
        return s
    }
}

/// Optional secondary tool (clearance/roughing).
struct OptionalToolPicker: View {
    var title: String
    @Binding var toolID: UUID?
    var library: ToolLibrary
    var kinds: [ToolKind]

    var body: some View {
        Picker(title, selection: $toolID) {
            Text("None").tag(UUID?.none)
            ForEach(library.tools.filter { kinds.contains($0.kind) }) { t in Text("T\(t.number) · \(t.name)").tag(Optional(t.id)) }
        }
    }
}
