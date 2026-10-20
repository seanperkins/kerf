import CADCore
import SwiftUI

/// Number style used by all length/feed fields.
let decimalFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...4)).grouping(.never)

/// Set by inspector sections: outside a `Form`, a `LabeledContent` row puts its field right after the
/// label, so the fields of different rows start at different x positions. Filling the row right-aligns
/// them on one edge. Forms (the sheets) align their own columns and leave this off.
private struct NumberFieldsFillRowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var numberFieldsFillRow: Bool {
        get { self[NumberFieldsFillRowKey.self] }
        set { self[NumberFieldsFillRowKey.self] = newValue }
    }
}

/// Labelled numeric field with a trailing unit.
struct NumberField: View {
    static let fieldWidth: CGFloat = 96
    @Environment(\.numberFieldsFillRow) private var fillRow
    var label: String
    @Binding var value: Double
    var unit: String = ""
    var help: String?

    init(_ label: String, value: Binding<Double>, unit: String = "", help: String? = nil) {
        self.label = label; self._value = value; self.unit = unit; self.help = help
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                // A fixed width, so the fields of every row share their right edge.
                ExpressionTextField(label: label, value: $value)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: NumberField.fieldWidth)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary).frame(minWidth: 34, alignment: .leading).fixedSize()
                }
            }
            .frame(maxWidth: fillRow ? .infinity : nil, alignment: .trailing)
        }
        .help(help ?? FieldHelp.text(for: label) ?? label)
        .accessibilityHint(unit)
    }
}

/// Length field in document units.
struct LengthField: View {
    var label: String
    @Binding var value: Double
    var units: LengthUnit
    var help: String?

    init(_ label: String, value: Binding<Double>, units: LengthUnit, help: String? = nil) {
        self.label = label; self._value = value; self.units = units; self.help = help
    }

    var body: some View { NumberField(label, value: $value, unit: units.abbreviation, help: help) }
}

/// Optional length: a checkbox enables it; unchecking stores nil.
struct OptionalLengthField: View {
    var label: String
    @Binding var value: Double?
    var units: LengthUnit
    var defaultValue: Double

    var body: some View {
        HStack {
            Toggle(label, isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? defaultValue) : nil }))
            Spacer()
            if value != nil {
                ExpressionTextField(label: label, value: Binding(get: { value ?? defaultValue }, set: { value = $0 }))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: NumberField.fieldWidth)
                Text(units.abbreviation).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            }
        }
        .help(FieldHelp.text(for: label) ?? label)
    }
}

struct IntField: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    init(_ label: String, value: Binding<Int>, range: ClosedRange<Int> = 0...10_000) {
        self.label = label; self._value = value; self.range = range
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: $value, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 50, maxWidth: 80)
                Stepper(label, value: $value, in: range).labelsHidden()
            }
        }
    }
}

extension LengthUnit {
    var displayName: String { self == .inch ? "Inches" : "Millimetres" }
    var feedUnit: String { self == .inch ? "in/min" : "mm/min" }
}

extension XYOrigin {
    var displayName: String {
        switch self {
        case .lowerLeft: return "Lower left"
        case .lowerRight: return "Lower right"
        case .upperLeft: return "Upper left"
        case .upperRight: return "Upper right"
        case .center: return "Centre"
        }
    }
}

extension ZZeroMode {
    var displayName: String { self == .materialTop ? "Material surface" : "Machine bed (spoilboard)" }
    /// For tight spaces such as the status bar.
    var shortName: String { self == .materialTop ? "Material" : "Bed" }
}

/// Open or closed state of collapsible inspector sections, remembered per section title.
enum SectionState {
    static func key(for title: String) -> String {
        let slug = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
        return "kerf.inspector.expanded." + slug
    }

    static func initiallyExpanded(collapsedByDefault: Bool) -> Bool { !collapsedByDefault }
}

/// Section header used in inspectors.
struct InspectorSection<Content: View>: View {
    var title: String
    /// Shows a "?" button that opens this help topic.
    var helpTopic: HelpTopic? = nil
    /// For a rarely changed group: a disclosure group that starts closed and remembers whether it was
    /// opened, so the common settings are not buried under every option.
    var collapsedByDefault = false
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if collapsedByDefault {
                CollapsibleSectionBody(title: title, helpTopic: helpTopic, content: content)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: title, helpTopic: helpTopic)
                    content
                }
            }
        }
        .environment(\.numberFieldsFillRow, true)
        .padding(.vertical, 4)
    }
}

private struct SectionHeader: View {
    var title: String
    var helpTopic: HelpTopic?

    var body: some View {
        HStack {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if let helpTopic {
                Spacer()
                HelpButton(topic: helpTopic).controlSize(.small)
            }
        }
    }
}

private struct CollapsibleSectionBody<Content: View>: View {
    var title: String
    var helpTopic: HelpTopic?
    var content: Content
    @AppStorage private var expanded: Bool

    init(title: String, helpTopic: HelpTopic?, content: Content) {
        self.title = title
        self.helpTopic = helpTopic
        self.content = content
        _expanded = AppStorage(wrappedValue: SectionState.initiallyExpanded(collapsedByDefault: true),
                               SectionState.key(for: title))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.top, 8)
        } label: {
            SectionHeader(title: title, helpTopic: helpTopic)
        }
    }
}

/// Borderless icon button with a hit target of at least `minimumSide` points. A bare SF Symbol is only
/// 10–17 pt, below the HIG minimum of 20 x 20 on macOS, and a borderless or plain button only
/// hit-tests the glyph itself.
struct IconButtonStyle: ButtonStyle {
    static let minimumSide: CGFloat = 22

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        IconButtonLabel(configuration: configuration)
    }

    private struct IconButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(minWidth: IconButtonStyle.minimumSide, minHeight: IconButtonStyle.minimumSide)
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.4)
        }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// A button under the fields it acts on, aligned to their trailing edge: Rotate, Move and Scale apply
/// a value on demand, unlike the fields above them that apply as they are edited.
struct ActionRow: View {
    var title: String
    var action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer()
            Button(title, action: action)
        }
    }
}
