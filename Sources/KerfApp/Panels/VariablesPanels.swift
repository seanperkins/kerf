import CADCore
import SwiftUI

// MARK: Expressions in numeric fields

private struct DocumentVariablesKey: EnvironmentKey {
    static let defaultValue: [String: Double] = [:]
}

private struct ExpressionUnitsKey: EnvironmentKey {
    static let defaultValue: LengthUnit? = nil
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
}

/// Number format whose parser accepts arithmetic, variables and unit suffixes.
struct ExpressionNumberStyle: ParseableFormatStyle {
    var variables: [String: Double]
    var units: LengthUnit?

    var parseStrategy: ExpressionParseStrategy { ExpressionParseStrategy(variables: variables, units: units) }

    func format(_ value: Double) -> String { decimalFormat.format(value) }
}

struct ExpressionParseStrategy: ParseStrategy {
    var variables: [String: Double]
    var units: LengthUnit?

    func parse(_ value: String) throws -> Double {
        try ExpressionEvaluator.evaluate(value, variables: variables, units: units)
    }
}

/// TextField for a Double that evaluates expressions (`=thickness/2`, `1/4in + 1mm`).
struct ExpressionTextField: View {
    var label: String
    @Binding var value: Double
    @Environment(\.documentVariables) private var variables
    @Environment(\.expressionUnits) private var units

    var body: some View {
        TextField(label, value: $value, format: ExpressionNumberStyle(variables: variables, units: units))
            .help("Type a number or an expression: + − × ÷ ^ ( ), variables such as =thickness, units like 1/4in or 6mm")
    }
}

// MARK: Variables editor

/// Design → Document Variables…: named values for numeric fields.
struct DocumentVariablesSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DocumentVariable]

    init(document: KerfDocument) {
        self.document = document
        _rows = State(initialValue: document.document.userVariables)
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
            Text("Type =name in any numeric field (e.g. =thickness - 0.05). Fields keep the value at the time it was typed. Built in: width, height, thickness, safez.")
                .font(.callout).foregroundStyle(.secondary)
            Table($rows) {
                TableColumn("Name") { $r in TextField("name", text: $r.name) }
                TableColumn("Value") { $r in
                    TextField("value", value: $r.value, format: decimalFormat).multilineTextAlignment(.trailing)
                }
                .width(110)
                TableColumn("") { $r in
                    Button { rows.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
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
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    let new = rows
                    document.perform("Edit Variables") { $0.document.userVariables = new }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!problems.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }
}
