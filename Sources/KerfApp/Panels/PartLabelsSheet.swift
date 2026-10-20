import CADCore
import CAMCore
import SwiftUI

/// Design > Layout > Label Parts…: engraves part numbers / names on parts.
struct PartLabelsSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @State private var options: PartLabelOptions
    @State private var fonts: [String] = []

    init(document: KerfDocument) {
        self.document = document
        _options = State(initialValue: PartLabelOptions.defaults(for: document.units))
    }

    private var targetIDs: [UUID] {
        let sel = document.selectedShapes.map(\.id)
        if !sel.isEmpty { return sel }
        return NestSheets.activeDocument(document.document).shapes.filter { document.project.isEditable($0) }.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Label Parts").font(.title3.bold())
            Text((document.selection.isEmpty ? "Every part on the material" : "The selected parts")
                 + " gets a label on the \"\(PartLabelCommands.layerName)\" layer, placed where the part has most room. "
                 + "Unnamed parts are named \"Part N\", and the job sheet lists them.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Label", selection: $options.text) {
                    ForEach(PartLabelText.allCases) { Text($0.title).tag($0) }
                }
                LengthField("Largest text height", value: $options.maxHeight, units: document.units)
                LengthField("Smallest text height", value: $options.minHeight, units: document.units,
                            help: "Parts too small for this size are not labelled")
                Picker("Font", selection: $options.fontName) {
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Add a V-Carve toolpath for the labels", isOn: $options.addToolpath)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Label") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(targetIDs.isEmpty || options.maxHeight <= 0)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            fonts = TextOutliner.availableFontNames()
            if !fonts.contains(options.fontName) { fonts.insert(options.fontName, at: 0) }
        }
    }

    private func run() {
        let ids = targetIDs, o = options, lib = document.mergedLibrary
        var report: PartLabelReport?
        var failure: Error?
        var p = document.project
        do {
            report = try PartLabelCommands.label(ids, options: o, library: lib, in: &p)
            let result = p
            document.perform("Label Parts") { $0 = result }
        } catch {
            failure = error
        }
        dismiss()
        if let failure {
            document.alert = AlertMessage(title: "Labels not added", message: ImportService.describe(failure))
        } else if let r = report {
            if let id = r.operationID {
                document.sidebarTab = .toolpaths
                document.selectedOperationID = id
            }
            if r.skipped > 0 {
                document.alert = AlertMessage(title: "Some parts were not labelled",
                                              message: "\(r.skipped) part(s) had no room for a label of the smallest text height.")
            }
        }
    }
}
