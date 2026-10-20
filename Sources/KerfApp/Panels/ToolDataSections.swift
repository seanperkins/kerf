import CADCore
import CAMCore
import SwiftUI

// Tool database additions (toolpaths-2d): groups, feeds calculator, per-material cutting data.

/// Section title for a tool in the database list: its group, else its type.
enum ToolGrouping {
    static func section(_ tool: Tool) -> String {
        if let g = tool.group?.trimmingCharacters(in: .whitespaces), !g.isEmpty {
            return g.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " › ")
        }
        return tool.kind.displayName
    }

    /// Sections in display order: named groups alphabetically, then the tool types.
    static func sections(_ tools: [Tool]) -> [(title: String, tools: [Tool])] {
        let grouped = Dictionary(grouping: tools, by: section)
        let kindTitles = ToolKind.allCases.map(\.displayName)
        let custom = grouped.keys.filter { !kindTitles.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return (custom + kindTitles).compactMap { title in
            grouped[title].map { (title, $0.sorted { $0.number < $1.number }) }
        }
    }

    /// Every material name used by any tool, sorted.
    static func materialNames(_ tools: [Tool]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for t in tools {
            for m in t.materials ?? [] where !m.material.isEmpty && !seen.contains(m.material.lowercased()) {
                seen.insert(m.material.lowercased())
                out.append(m.material)
            }
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct ToolGroupSection: View {
    @Binding var tool: Tool
    var existingGroups: [String]

    var body: some View {
        Section("Organization") {
            HStack {
                TextField("Group", text: Binding(get: { tool.group ?? "" }, set: { tool.group = $0.isEmpty ? nil : $0 }),
                          prompt: Text(tool.kind.displayName))
                if !existingGroups.isEmpty {
                    Menu {
                        ForEach(existingGroups, id: \.self) { g in Button(g) { tool.group = g } }
                        Divider()
                        Button("No Group") { tool.group = nil }
                    } label: { Image(systemName: "folder") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            Text("Folder in the tool list; use \"/\" for sub-folders. Empty = listed under its type.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FeedsCalculatorSection: View {
    @Binding var tool: Tool
    @State private var chipLoad: Double = 0

    var body: some View {
        let u = tool.units
        let current = FeedsAndSpeeds.chipLoad(feedRate: tool.feedRate, rpm: tool.spindleRPM, flutes: tool.flutes)
        let feed = FeedsAndSpeeds.feedRate(rpm: tool.spindleRPM, flutes: tool.flutes, chipLoad: chipLoad)
        Section("Feeds calculator") {
            LabeledContent("Current chip load") {
                Text("\(current, format: .number.precision(.fractionLength(0...4))) \(u.abbreviation)/tooth")
            }
            LabeledContent("Surface speed") {
                let s = FeedsAndSpeeds.surfaceSpeed(diameter: tool.diameter, rpm: tool.spindleRPM, units: u)
                Text("\(s, format: .number.precision(.fractionLength(0))) \(FeedsAndSpeeds.surfaceSpeedUnit(u))")
            }
            NumberField("Target chip load", value: $chipLoad, unit: "\(u.abbreviation)/tooth",
                        help: "Advance per cutting edge; check your bit maker's chart for the material")
            HStack {
                Text("Feed = \(Int(tool.spindleRPM)) RPM × \(tool.flutes) flutes × chip load = \(feed, format: .number.precision(.fractionLength(0...1))) \(u.feedUnit)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { tool.feedRate = feed }.disabled(feed <= 0)
            }
        }
        .onAppear { chipLoad = (current * 10000).rounded() / 10000 }
    }
}

struct MaterialDataSection: View {
    @Binding var tool: Tool
    var knownMaterials: [String]

    private var list: [MaterialCuttingData] { tool.materials ?? [] }

    private func binding<T>(_ i: Int, _ kp: WritableKeyPath<MaterialCuttingData, T>) -> Binding<T> {
        Binding(get: { list[i][keyPath: kp] }, set: { v in
            var l = list
            guard l.indices.contains(i) else { return }
            l[i][keyPath: kp] = v
            tool.materials = l
        })
    }

    var body: some View {
        let u = tool.units
        Section("Cutting data per material") {
            ForEach(Array(list.enumerated()), id: \.offset) { i, _ in
                DisclosureGroup {
                    NumberField("Spindle speed", value: binding(i, \.spindleRPM), unit: "RPM")
                    NumberField("Feed rate", value: binding(i, \.feedRate), unit: u.feedUnit)
                    NumberField("Plunge rate", value: binding(i, \.plungeRate), unit: u.feedUnit)
                    LengthField("Pass depth", value: binding(i, \.stepdown), units: u)
                    LengthField("Stepover", value: binding(i, \.stepover), units: u)
                    Button("Remove", role: .destructive) {
                        var l = list
                        l.remove(at: i)
                        tool.materials = l.isEmpty ? nil : l
                    }
                } label: {
                    TextField("Material", text: binding(i, \.material))
                }
            }
            Menu {
                Button("New Material") { add("Material \(list.count + 1)") }
                ForEach(knownMaterials.filter { m in !list.contains { $0.material.caseInsensitiveCompare(m) == .orderedSame } },
                        id: \.self) { m in Button(m) { add(m) } }
            } label: { Label("Add Material", systemImage: "plus") }
            .fixedSize()
            Text("The values above are the defaults. When Job Setup names a material listed here, toolpaths use its values instead.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func add(_ name: String) {
        tool.materials = list + [MaterialCuttingData(material: name, from: tool)]
    }
}

/// Per-toolpath overrides of the primary tool's cutting data (document units).
struct ToolOverrideSection: View {
    @Binding var override: ToolOverride?
    var tool: Tool?
    var units: LengthUnit

    private func field(_ kp: WritableKeyPath<ToolOverride, Double?>) -> Binding<Double?> {
        Binding(get: { override?[keyPath: kp] }, set: { v in
            var o = override ?? ToolOverride()
            o[keyPath: kp] = v
            override = o.isEmpty ? nil : o
        })
    }

    var body: some View {
        DisclosureGroup("Tool overrides\(override == nil ? "" : " (on)")") {
            OptionalValueField(label: "Spindle speed", value: field(\.spindleRPM), unit: "RPM", defaultValue: tool?.spindleRPM ?? 18000)
            OptionalValueField(label: "Feed rate", value: field(\.feedRate), unit: units.feedUnit, defaultValue: tool?.feedRate ?? 60)
            OptionalValueField(label: "Plunge rate", value: field(\.plungeRate), unit: units.feedUnit, defaultValue: tool?.plungeRate ?? 20)
            OptionalValueField(label: "Pass depth", value: field(\.stepdown), unit: units.abbreviation, defaultValue: tool?.stepdown ?? 0.1)
            OptionalValueField(label: "Stepover", value: field(\.stepover), unit: units.abbreviation, defaultValue: tool?.stepover ?? 0.1)
            Text("Changes this toolpath only; the tool database is not changed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Optional number with a unit label: a checkbox enables it; unchecking stores nil.
struct OptionalValueField: View {
    var label: String
    @Binding var value: Double?
    var unit: String
    var defaultValue: Double

    var body: some View {
        HStack {
            Toggle(label, isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? defaultValue) : nil }))
            Spacer()
            if value != nil {
                TextField(label, value: Binding(get: { value ?? defaultValue }, set: { value = $0 }), format: decimalFormat)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 60, maxWidth: 110)
                Text(unit).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            }
        }
    }
}

/// Job material name, with a menu of the materials tools have cutting data for.
struct MaterialNameField: View {
    @Binding var material: String?
    var known: [String]

    var body: some View {
        HStack {
            TextField("Material type", text: Binding(get: { material ?? "" },
                                                    set: { material = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }),
                      prompt: Text("Any"))
            if !known.isEmpty {
                Menu {
                    ForEach(known, id: \.self) { m in Button(m) { material = m } }
                    Divider()
                    Button("Any (tool defaults)") { material = nil }
                } label: { Image(systemName: "list.bullet") }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        Text("Tools with cutting data for this material use it; others use their defaults.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
