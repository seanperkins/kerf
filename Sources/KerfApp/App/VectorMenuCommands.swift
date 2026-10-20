import CADCore
import CAMCore
import SwiftUI

/// The "Vectors" menu: drawing-area tools that act on the selected vectors (kept apart from
/// `KerfCommands` so the Design menu stays short).
struct VectorMenuCommands: Commands {
    @FocusedObject private var document: KerfDocument?

    var body: some Commands {
        CommandMenu("Vectors") {
            sheetButton("Rectangular Array…", .arrayLinear)
            Divider()
            sheetButton("Dog-bone Fillets…", .dogbone)
            Divider()
            sheetButton("Validate Vectors…", .validator, needsSelection: false)
            Button("Clear Problem Markers") { document?.highlightMarkers = [] }
                .disabled(document?.highlightMarkers.isEmpty ?? true)
        }
    }

    private var noSelection: Bool { document?.selection.isEmpty ?? true }

    private func sheetButton(_ title: String, _ kind: DrawingSheet, needsSelection: Bool = true) -> some View {
        Button(title) { document?.sheet = .drawing(kind) }
            .disabled(document == nil || (needsSelection && noSelection))
    }
}
