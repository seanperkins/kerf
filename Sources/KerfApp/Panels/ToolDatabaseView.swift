import CADCore
import CAMCore
import SwiftUI

/// Tool Database window: list of tools + editor. Changes save to tools.json immediately.
struct ToolDatabaseView: View {
    static let windowID = "tool-database"
    @EnvironmentObject var library: ToolLibraryModel
    @State private var selectedID: UUID?

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
        .overlay(alignment: .bottom) {
            if let e = library.lastError {
                Text(e).font(.caption).foregroundStyle(.red).padding(6).background(.regularMaterial)
            }
        }
    }
}

struct ToolEditor: View {
    @EnvironmentObject var library: ToolLibraryModel
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
            Section("Tool") {
                TextField("Name", text: $tool.name)
                Picker("Type", selection: $tool.kind) {
                    ForEach(ToolKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                IntField("Tool number", value: $tool.number, range: 0...999)
                Picker("Units", selection: Binding(get: { tool.units }, set: { tool = tool.converted(to: $0) })) {
                    ForEach(LengthUnit.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
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
                    Text("The Avid 2.2 kW spindle runs 6000–24000 RPM.").font(.caption).foregroundStyle(.orange)
                }
            }
            FeedsCalculatorSection(tool: $tool)
            MaterialDataSection(tool: $tool, knownMaterials: ToolGrouping.materialNames(library.tools))
            ToolGroupSection(tool: $tool, existingGroups: Array(Set(library.tools.compactMap(\.group))).sorted())
            Section("Notes") {
                TextEditor(text: $tool.notes).frame(minHeight: 60)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Revert") { tool = original }.disabled(tool == original)
                    Button("Save") { library.update(tool) }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(tool == original)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: tool.kind) { _, k in
            if (k == .vBit || k == .engraving) && tool.angle == nil { tool.angle = 60 }
        }
    }
}
