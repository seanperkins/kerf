import CADCore
import CAMCore
import SwiftUI

/// The "Vectors" menu: drawing-area tools that act on the selected vectors (kept apart from
/// `KerfCommands` so the Design menu stays short).
struct VectorMenuCommands: Commands {
    @FocusedObject private var document: KerfDocument?

    var body: some Commands {
        CommandMenu("Vectors") {
            sheetButton("Mirror…", .mirror)
            Divider()
            sheetButton("Rectangular Array…", .arrayLinear)
            Divider()
            Button("Trim Tool") { document?.activeTool = .trim }.disabled(document == nil)
            sheetButton("Trim to Boundary…", .trimBoundary)
            Divider()
            sheetButton("Fillet / Chamfer Corners…", .filletChamfer)
            sheetButton("Dog-bone Fillets…", .dogbone)
            Divider()
            Toggle("Snap to Guides", isOn: Binding(get: { document?.snapToGuides ?? true }, set: { document?.snapToGuides = $0 }))
            Button("Clear Guides") { document?.perform("Clear Guides") { $0.document.guides = nil } }
                .disabled(document?.document.guides?.isEmpty ?? true)
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
