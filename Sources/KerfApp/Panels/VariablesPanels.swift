import CADCore
import CAMCore
import SwiftUI

// MARK: Expressions in numeric fields

private struct DocumentVariablesKey: EnvironmentKey {
    static let defaultValue: [String: Double] = [:]
}

private struct ExpressionUnitsKey: EnvironmentKey {
    static let defaultValue: LengthUnit? = nil
}

private struct ExpressionRecorderKey: EnvironmentKey {
    static let defaultValue: ExpressionRecorder? = nil
}

extension EnvironmentValues {
    /// Variables usable in numeric fields of the current document window.
    var documentVariables: [String: Double] {
        get { self[DocumentVariablesKey.self] }
        set { self[DocumentVariablesKey.self] = newValue }
    }

    /// Document units for unit suffixes typed in numeric fields ("2in", "6mm").
    var expressionUnits: LengthUnit? {
        get { self[ExpressionUnitsKey.self] }
        set { self[ExpressionUnitsKey.self] = newValue }
    }

    /// Where numeric fields note expressions that use variables, so the parameter they set
    /// stays linked (see `VariableLinks`).
    var expressionRecorder: ExpressionRecorder? {
        get { self[ExpressionRecorderKey.self] }
        set { self[ExpressionRecorderKey.self] = newValue }
    }
}

/// Number format whose parser accepts arithmetic, variables and unit suffixes.
struct ExpressionNumberStyle: ParseableFormatStyle {
    var variables: [String: Double]
    var units: LengthUnit?
    var recorder: ExpressionRecorder?

    init(variables: [String: Double], units: LengthUnit?, recorder: ExpressionRecorder? = nil) {
        self.variables = variables; self.units = units; self.recorder = recorder
    }

    var parseStrategy: ExpressionParseStrategy {
        ExpressionParseStrategy(variables: variables, units: units, recorder: recorder)
    }

    func format(_ value: Double) -> String { decimalFormat.format(value) }

    // The recorder is a reference to the window's document; it takes no part in identity.
    private enum CodingKeys: String, CodingKey { case variables, units }
    static func == (a: Self, b: Self) -> Bool { a.variables == b.variables && a.units == b.units }
    func hash(into h: inout Hasher) { h.combine(variables); h.combine(units) }
}

struct ExpressionParseStrategy: ParseStrategy {
    var variables: [String: Double]
    var units: LengthUnit?
    var recorder: ExpressionRecorder?

    init(variables: [String: Double], units: LengthUnit?, recorder: ExpressionRecorder? = nil) {
        self.variables = variables; self.units = units; self.recorder = recorder
    }

    func parse(_ value: String) throws -> Double {
        let v = try ExpressionEvaluator.evaluate(value, variables: variables, units: units)
        recorder?.note(value, value: v, units: units)
        return v
    }

    private enum CodingKeys: String, CodingKey { case variables, units }
    static func == (a: Self, b: Self) -> Bool { a.variables == b.variables && a.units == b.units }
    func hash(into h: inout Hasher) { h.combine(variables); h.combine(units) }
}

/// TextField for a Double that evaluates expressions (`=thickness/2`, `1/4in + 1mm`). An
/// expression that uses a variable stays linked to the parameter it sets.
struct ExpressionTextField: View {
    var label: String
    @Binding var value: Double
    @Environment(\.documentVariables) private var variables
    @Environment(\.expressionUnits) private var units
    @Environment(\.expressionRecorder) private var recorder

    var body: some View {
        TextField(label, value: Binding(get: { value }, set: { new in
            value = recorder?.valueToWrite(new, current: value) ?? new
        }), format: ExpressionNumberStyle(variables: variables, units: units, recorder: recorder))
            .help("Type a number or an expression: + − × ÷ ^ ( ), variables such as =thickness (the field stays linked to it), units like 1/4in or 6mm")
    }
}

// MARK: Variables editor

/// Design → Document Variables…: named values for numeric fields.
struct DocumentVariablesSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DocumentVariable]
    @State private var links: [VariableLink]

    init(document: KerfDocument) {
        self.document = document
        _rows = State(initialValue: document.document.userVariables)
        _links = State(initialValue: document.document.linkedValues)
    }

    /// The project as it would be after OK (for link labels and failures).
    private var preview: KerfProject {
        var p = document.project
        p.document.userVariables = rows
        p.document.linkedValues = links
        return p
    }

    private var problems: [String] {
        var out: [String] = []
        var seen = Set<String>()
        for r in rows {
            if !DocumentVariable.isValidName(r.name) { out.append("\"\(r.name)\" is not a valid name (letters, digits, _).") }
            if !seen.insert(r.name.lowercased()).inserted { out.append("\"\(r.name)\" is used twice.") }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Document Variables").font(.title2.bold())
            Text("Type =name in any numeric field (e.g. =thickness - 0.05). Job Setup and toolpath fields stay linked: they update when a variable or the material changes, until you type a plain number over them. Built in: width, height, thickness, safez.")
                .font(.callout).foregroundStyle(.secondary)
            Table($rows) {
                TableColumn("Name") { $r in TextField("name", text: $r.name) }
                TableColumn("Value") { $r in
                    TextField("value", value: $r.value, format: decimalFormat).multilineTextAlignment(.trailing)
                }
                .width(110)
                TableColumn("") { $r in
                    Button { rows.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.icon)
                }
                .width(30)
            }
            .frame(minHeight: 180)
            Button {
                var n = rows.count + 1
                while rows.contains(where: { $0.name == "var\(n)" }) { n += 1 }
                rows.append(DocumentVariable(name: "var\(n)", value: 0))
            } label: { Label("Add Variable", systemImage: "plus") }
            ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if !links.isEmpty {
                Text("Linked fields").font(.headline)
                let p = preview
                List {
                    ForEach(links) { l in
                        HStack {
                            Text(VariableLinks.describe(l, in: p)).lineLimit(1)
                            Spacer()
                            if let v = VariableLinks.evaluate(l, in: p) {
                                Text("\(l.expression) = \(decimalFormat.format(v))").foregroundStyle(.secondary)
                            } else {
                                Label("\(l.expression): unknown name", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                            Button("Unlink") { links.removeAll { $0.id == l.id } }
                                .buttonStyle(.borderless)
                                .help("Keep the current value but stop following the expression")
                        }
                    }
                }
                .frame(minHeight: 70, maxHeight: 120)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    let new = rows, newLinks = links
                    document.perform("Edit Variables") {
                        $0.document.userVariables = new
                        $0.document.linkedValues = newLinks
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!problems.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: links.isEmpty ? 420 : 560)
    }
}
