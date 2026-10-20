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
