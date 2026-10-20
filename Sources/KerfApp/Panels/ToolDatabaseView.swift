import CADCore
import CAMCore
import SwiftUI
import UniformTypeIdentifiers

/// Tool Database window: list of tools + editor. Edits save to tools.json as they are made
/// (and once more when the editor closes), so switching tools or closing the window never drops them.
struct ToolDatabaseView: View {
    static let windowID = "tool-database"
    @EnvironmentObject var library: ToolLibraryModel
    @State private var selectedID: UUID?
    @State private var pendingImport: [Tool]?
    @State private var pendingConflicts = 0
    @State private var importMessage: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(ToolGrouping.sections(library.tools), id: \.title) { section in
                    let tools = section.tools
                    if !tools.isEmpty {
                        Section(section.title) {
                            ForEach(tools) { t in
                                HStack {
                                    Text("T\(t.number)").monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                                    Text(t.name).lineLimit(1)
                                }
                                .tag(t.id)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem {
                    Menu {
                        ForEach(ToolKind.allCases, id: \.self) { kind in
                            Button(kind.displayName) { selectedID = library.add(kind: kind).id }
                        }
                        Divider()
                        Button("Bull Nose End Mill") { selectedID = library.add(kind: .endMill, shape: .bullNose).id }
                        Button("Tapered Ball Nose") { selectedID = library.add(kind: .ballNose, shape: .tapered).id }
                        Button("Form Tool") { selectedID = library.add(kind: .endMill, shape: .form).id }
                    } label: { Label("Add Tool", systemImage: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Duplicate") { if let id = selectedID { selectedID = library.duplicate(id: id)?.id } }
                        .disabled(selectedID == nil)
                    Button("Delete") { if let id = selectedID { library.delete(id: id); selectedID = nil } }
                        .disabled(selectedID == nil)
                    Spacer()
                    Menu("Share") {
                        Button("Import Tools…") { runImport() }
                        Divider()
                        Button("Export All Tools…") { runExport(ids: nil) }
                        Button("Export Selected Tool…") { if let id = selectedID { runExport(ids: [id]) } }
                            .disabled(selectedID == nil)
                    }
                    .fixedSize()
                    .help("Import or export tools as a .kerftools file (or CSV) to share them between machines")
                    Button("Restore Defaults") { library.restoreDefaults() }
                        .help("Re-adds any missing default tools")
                }
                .padding(8)
            }
        } detail: {
            if let id = selectedID, let tool = library.library.tool(id: id) {
                ToolEditor(original: tool).id(id)
            } else {
                Text("Select a tool").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .confirmationDialog("\(pendingConflicts) imported tool\(pendingConflicts == 1 ? "" : "s") already exist with different settings",
                            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace Existing") { finishImport(.replace) }
            Button("Keep Both") { finishImport(.keepBoth) }
            Button("Keep Existing (Skip)") { finishImport(.skip) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Replace overwrites your tools with the imported ones. Keep Both adds the imported tools as new tools.")
        }
        .alert("Import Tools", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
        .overlay(alignment: .bottom) {
            if let e = library.lastError {
                Text(e).font(.caption).foregroundStyle(Color.errorText).padding(6).background(.regularMaterial)
            }
        }
    }
}

extension ToolDatabaseView {
    private static var exchangeTypes: [UTType] {
        [UTType(filenameExtension: ToolLibraryExchange.fileExtension, conformingTo: .json), .json, .commaSeparatedText]
            .compactMap { $0 }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.exchangeTypes
        panel.message = "Import tools from a .kerftools file, another Mac's tools.json, or a CSV file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let (tools, conflicts) = try library.readImport(url)
            if conflicts.isEmpty {
                importMessage = library.importTools(tools, policy: .keepBoth).summary
            } else {
                pendingConflicts = conflicts.count
                pendingImport = tools
            }
        } catch {
            importMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func finishImport(_ policy: ToolImportPolicy) {
        guard let tools = pendingImport else { return }
        pendingImport = nil
        importMessage = library.importTools(tools, policy: policy).summary
    }

    private func runExport(ids: Set<UUID>?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.exchangeTypes
        let base = ids.flatMap { $0.first }.flatMap { library.library.tool(id: $0)?.name } ?? "Kerf Tools"
        panel.nameFieldStringValue = base.replacingOccurrences(of: "/", with: "-") + "." + ToolLibraryExchange.fileExtension
        panel.message = "Export tools (.kerftools keeps everything; .csv for spreadsheets — choose by file extension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try library.export(ids: ids, to: url) } catch {
            importMessage = "Could not export: \(error.localizedDescription)"
        }
    }
}

struct ToolEditor: View {
    @EnvironmentObject var library: ToolLibraryModel
    /// The tool as it was when this editor opened (what Revert goes back to).
    let original: Tool
    @State private var tool: Tool

    init(original: Tool) {
        self.original = original
        _tool = State(initialValue: original)
    }

    private var isAngled: Bool { tool.kind == .vBit || tool.kind == .engraving }

    var body: some View {
        let u = tool.units
        Form {
            Section {
                TextField("Name", text: $tool.name)
                Picker("Type", selection: $tool.kind) {
                    ForEach(ToolKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                    .fieldHelp("Type")
                IntField("Tool number", value: $tool.number, range: 0...999)
                Picker("Units", selection: Binding(get: { tool.units }, set: { tool = tool.converted(to: $0) })) {
                    ForEach(LengthUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                    .fieldHelp("Units")
            } header: {
                HStack { Text("Tool"); Spacer(); HelpButton(topic: .toolDatabase).controlSize(.small) }
            }
            Section("Geometry") {
                LengthField("Diameter", value: $tool.diameter, units: u)
                IntField("Flutes", value: $tool.flutes, range: 1...8)
                if isAngled {
                    NumberField("Included angle", value: Binding(get: { tool.angle ?? 60 }, set: { tool.angle = $0 }), unit: "°")
                    LengthField("Tip diameter", value: $tool.tipDiameter, units: u)
                }
                OptionalLengthField(label: "Flute length", value: $tool.fluteLength, units: u, defaultValue: tool.diameter * 3)
            }
            Section("Cutting data") {
                LengthField("Pass depth (stepdown)", value: $tool.stepdown, units: u)
                if !(tool.stepdown > 0) {
                    Text("Pass depth must be positive; toolpaths using this tool will not calculate.")
                        .font(.caption).foregroundStyle(Color.errorText)
                }
                LabeledContent("Stepover") {
                    HStack {
                        TextField("Stepover", value: $tool.stepover, format: decimalFormat)
                            .labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 90)
                        Text(u.abbreviation).foregroundStyle(.secondary)
                        TextField("%", value: Binding(get: { tool.diameter > 0 ? tool.stepover / tool.diameter * 100 : 0 },
                                                      set: { tool.stepover = tool.diameter * $0 / 100 }),
                                  format: .number.precision(.fractionLength(0...1)))
                            .labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 60)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                NumberField("Spindle speed", value: $tool.spindleRPM, unit: "RPM")
                NumberField("Feed rate", value: $tool.feedRate, unit: u.feedUnit)
                NumberField("Plunge rate", value: $tool.plungeRate, unit: u.feedUnit)
                if tool.spindleRPM < 6000 || tool.spindleRPM > 24000 {
                    Text("The Avid 2.2 kW spindle runs 6000–24000 RPM.").font(.caption).foregroundStyle(Color.warningText)
                }
            }
            ToolShapeSection(tool: $tool)
            FeedsCalculatorSection(tool: $tool, jobMaterial: library.jobMaterial)
            MaterialDataSection(tool: $tool, knownMaterials: ToolGrouping.materialNames(library.tools))
            ToolGroupSection(tool: $tool, existingGroups: Array(Set(library.tools.compactMap(\.group))).sorted())
            Section("Notes") {
                TextEditor(text: $tool.notes).frame(minHeight: 60)
            }
            Section {
                HStack {
                    Spacer()
                    Text(tool == original ? "Changes save automatically." : "Changes saved.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Revert Changes") { tool = original }
                        .help("Go back to the settings this tool had when you selected it")
                        .disabled(tool == original)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: tool.kind) { _, k in
            if (k == .vBit || k == .engraving) && tool.angle == nil { tool.angle = 60 }
        }
        .onChange(of: tool) { _, t in library.commitEdit(t) }
        .onDisappear { library.commitEdit(tool) }
    }
}
