import CADCore
import SwiftUI

/// Number style used by all length/feed fields.
let decimalFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...4)).grouping(.never)

/// Labelled numeric field with a trailing unit.
struct NumberField: View {
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
                ExpressionTextField(label: label, value: $value)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 60, maxWidth: 110)
                if !unit.isEmpty {
                    Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                }
            }
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
                    .frame(minWidth: 60, maxWidth: 110)
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

/// Section header used in inspectors.
struct InspectorSection<Content: View>: View {
    var title: String
    /// Shows a "?" button that opens this help topic.
    var helpTopic: HelpTopic? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                if let helpTopic {
                    Spacer()
                    HelpButton(topic: helpTopic).controlSize(.small)
                }
            }
            content
        }
        .padding(.vertical, 4)
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
