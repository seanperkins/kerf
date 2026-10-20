import AppKit
import CADCore
import CAMCore
import SwiftUI
import UniformTypeIdentifiers

/// Dialogs added by the io workstream, shown through `DocumentSheet.io`.
enum IOSheet: Equatable {
    case modelParts(ModelPartsForm)

    var id: String {
        switch self {
        case .modelParts(let f): return "parts-\(f.id)"
        }
    }
}

struct IOSheetHost: View {
    @ObservedObject var document: KerfDocument
    var sheet: IOSheet

    var body: some View {
        switch sheet {
        case .modelParts(let form): ModelPartsSheet(document: document, form: form)
        }
    }
}

// MARK: Import 3D model as 2D parts

extension KerfDocument {
    /// File > Import 3D Model as 2D Parts…
    func runModelPartsPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = (ModelPartsForm.allowedExtensions + ["skp"]).compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a 3D model (COLLADA .dae from SketchUp, STL or OBJ) to cut as flat parts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            sheet = .io(.modelParts(try ModelPartsForm.read(data: data, fileName: url.lastPathComponent, units: units)))
        } catch {
            alert = AlertMessage(title: "Import", message: "\(url.lastPathComponent): \(ImportService.describe(error))")
        }
    }

    func importModelParts(_ form: ModelPartsForm) {
        var outcome = ImportOutcome()
        perform("Import Parts") { outcome = form.apply(to: &$0) }
        if !outcome.shapeIDs.isEmpty {
            setSelection(outcome.shapeIDs)
            sidebarTab = .design
            requestCanvas(.fit)
        }
        if !outcome.warnings.isEmpty {
            deferredAlert = AlertMessage(title: "Import Parts", message: outcome.warnings.joined(separator: "\n"))
        }
    }
}

struct ModelPartsSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @State private var form: ModelPartsForm
    @State private var summary: [(String, Int)] = []

    init(document: KerfDocument, form: ModelPartsForm) {
        self.document = document
        _form = State(initialValue: form)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import 3D Model as 2D Parts").font(.title2.bold())
            Text("\(form.fileName): \(form.parts.count) part\(form.parts.count == 1 ? "" : "s"). Each part becomes a closed outline (with any through-holes) to cut with a Profile toolpath.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Outline", selection: $form.view) {
                    ForEach(MeshParts.View.allCases, id: \.self) { Text(ModelPartsForm.viewTitle($0)).tag($0) }
                }
                LengthField("Gap between parts", value: $form.gap, units: document.units)
                    .disabled(form.view != .flat)
                Toggle("One layer per part thickness", isOn: $form.layerPerThickness)
                    .disabled(form.view != .flat)
            }
            if !summary.isEmpty {
                Text("Thicknesses").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(summary, id: \.0) { row in Text("\(row.0): \(row.1) part\(row.1 == 1 ? "" : "s")") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
            Text("Pockets, grooves and other features inside a part are not converted; only its outline and holes that go right through.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    let f = form
                    dismiss()
                    document.importModelParts(f)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(form.gap < 0)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { summary = form.thicknessSummary(units: document.units) }
    }
}
