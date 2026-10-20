import AppKit
import CADCore
import CAMCore
import SwiftUI

/// Fit text to a box: scales and centres the selected text in another selected vector's
/// bounding box (or the material).
struct TextFitSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var margin: Double
    @State private var stretch = false

    init(document: KerfDocument) {
        self.document = document
        _margin = State(initialValue: document.units == .inch ? 0.25 : 6)
    }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let hasText = document.selectedShapes.contains { $0.text != nil }
        let hasBox = document.selectedShapes.contains { $0.text == nil }
        DrawingDialog(title: "Fit Text to Box", action: "Fit", disabled: !hasText,
                      note: !hasText ? "Select live text (and optionally a boundary vector)."
                          : hasBox ? "The text fills the selected boundary's bounding box." : "No boundary selected: the text fills the material.",
                      perform: {
                          let (m, s) = (margin, stretch)
                          document.perform("Fit Text") { VectorCommands.fitTextToBox(ids, margin: m, stretch: s, in: &$0) }
                      }) {
            LengthField("Margin", value: $margin, units: document.units)
            Toggle("Stretch to fill (change proportions)", isOn: $stretch)
        }
    }
}

/// Text on a curve / arc text.
struct TextOnCurveSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var useCurve = true
    @State private var radius: Double
    @State private var convex = true
    @State private var placement = TextOnPath.Placement.center
    @State private var offset = 0.0
    @State private var flip = false
    @State private var keepOriginal = false

    init(document: KerfDocument) {
        self.document = document
        _radius = State(initialValue: document.units == .inch ? 6 : 150)
    }

    var body: some View {
        let text = document.selectedShapes.first { $0.text != nil }
        let curve = document.selectedShapes.first { $0.text == nil && !$0.paths.isEmpty }
        let onCurve = useCurve && curve != nil
        DrawingDialog(title: "Text on Curve", action: "Place Text", disabled: text == nil || (!onCurve && radius <= 0),
                      note: text == nil ? "Select live text, plus the curve to follow."
                          : onCurve ? "The text follows the selected vector from its start point; it becomes plain vectors."
                          : "The text is bent round a circle of this radius; it becomes plain vectors.",
                      perform: {
                          guard let t = text else { return }
                          let (c, r, cv, pl, o, f, k) = (onCurve ? curve?.id : nil, radius, convex, placement, offset, flip, keepOriginal)
                          var newID: UUID?
                          do {
                              var p = document.project
                              newID = try VectorCommands.textOnCurve(textID: t.id, curveID: c, bendRadius: r, convex: cv, placement: pl,
                                                                      offset: o, flip: f, keepOriginal: k, in: &p)
                              let updated = p
                              document.perform("Text on Curve") { $0 = updated }
                          } catch {
                              document.alert = AlertMessage(title: "Text", message: ImportService.describe(error))
                          }
                          if let id = newID { document.setSelection([id]) }
                      }) {
            if curve != nil {
                Picker("Shape", selection: $useCurve) {
                    Text("Follow selected vector").tag(true)
                    Text("Bend into arc").tag(false)
                }
            }
            if onCurve {
                Picker("Position", selection: $placement) {
                    Text("From start").tag(TextOnPath.Placement.start)
                    Text("Centred").tag(TextOnPath.Placement.center)
                    Text("To end").tag(TextOnPath.Placement.end)
                }
                LengthField("Offset from curve", value: $offset, units: document.units)
                Toggle("Other side (reverse direction)", isOn: $flip)
            } else {
                LengthField("Arc radius", value: $radius, units: document.units)
                Picker("Bend", selection: $convex) {
                    Text("Arch up").tag(true)
                    Text("Smile down").tag(false)
                }
                .pickerStyle(.segmented)
            }
            Toggle("Keep the original text", isOn: $keepOriginal)
        }
    }
}

/// Justification, line spacing and letter spacing fields (text tool and text inspector).
struct TextLayoutFields: View {
    @Binding var alignment: CADCore.TextAlignment
    @Binding var lineSpacing: Double
    @Binding var letterSpacing: Double
    var units: LengthUnit

    var body: some View {
        Picker("Justify", selection: $alignment) {
            Image(systemName: "text.alignleft").tag(CADCore.TextAlignment.left).help("Left")
            Image(systemName: "text.aligncenter").tag(CADCore.TextAlignment.center).help("Centre")
            Image(systemName: "text.alignright").tag(CADCore.TextAlignment.right).help("Right")
        }
        .pickerStyle(.segmented)
        NumberField("Line spacing", value: $lineSpacing, unit: "×", help: "Multiple of the font's normal line height")
        LengthField("Letter spacing", value: $letterSpacing, units: units, help: "Extra space after each letter (negative tightens)")
    }
}

/// Inspector section for a live text shape: edit the string, font, size, justification and
/// spacing, or convert to plain curves.
struct TextEditSection: View {
    @ObservedObject var document: KerfDocument
    var shape: Shape
    @State private var draft = TextSpec(string: "", fontName: "Helvetica", size: 1)
    @State private var height = 1.0
    @State private var letterSpacing = 0.0
    @State private var fonts: [String] = []

    var body: some View {
        InspectorSection(title: "Text") {
            TextField("Text", text: $draft.string, axis: .vertical).lineLimit(1...8)
            Picker("Font", selection: $draft.fontName) {
                ForEach(fonts, id: \.self) { Text($0).tag($0) }
            }
            LengthField("Height", value: $height, units: document.units, help: "Capital letter height")
            TextLayoutFields(alignment: $draft.alignment, lineSpacing: $draft.lineSpacing,
                             letterSpacing: $letterSpacing, units: document.units)
            HStack {
                Button("Apply") { apply() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || height <= 0)
                Button("Revert") { load() }
                Spacer()
                Button("Convert to Curves") {
                    let id = shape.id
                    document.perform("Convert to Curves") { VectorCommands.convertTextToCurves([id], in: &$0) }
                }
                .help("Make the text plain vectors (needed for node editing)")
            }
        }
        .onAppear {
            fonts = TextOutliner.availableFontNames()
            if fonts.isEmpty { fonts = NSFontManager.shared.availableFontFamilies }
            fonts.insert(StrokeFont.name, at: 0)
            load()
        }
        .onChange(of: shape.text) { _, _ in load() }
    }

    private func load() {
        guard let t = shape.text else { return }
        draft = t
        height = t.displayedSize
        letterSpacing = t.letterSpacing * t.scale
        if !fonts.contains(t.fontName) { fonts.insert(t.fontName, at: 0) }
    }

    private func apply() {
        guard let t = shape.text, t.scale > 0 else { return }
        var spec = draft
        spec.transform = t.transform
        spec.size = height / t.scale
        spec.letterSpacing = letterSpacing / t.scale
        let id = shape.id
        do {
            var p = document.project
            try VectorCommands.updateText(id, spec: spec, in: &p)
            let updated = p
            document.perform("Edit Text") { $0 = updated }
        } catch {
            document.alert = AlertMessage(title: "Text", message: ImportService.describe(error))
        }
    }
}
