import CADCore
import CAMCore
import SwiftUI

struct MirrorSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var horizontally = true
    @State private var pivot = VectorCommands.MirrorPivot.selectionCenter
    @State private var keepOriginal = false

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        DrawingDialog(title: "Mirror", action: keepOriginal ? "Mirror Copy" : "Mirror", disabled: ids.isEmpty,
                      note: "Mirroring about the material centre flips a design for cutting from the back of the board.",
                      perform: {
                          let (h, p, k) = (horizontally, pivot, keepOriginal)
                          var copies: [UUID]?
                          document.perform(k ? "Mirror Copy" : "Mirror") {
                              copies = VectorCommands.mirror(ids, horizontally: h, pivot: p, keepOriginal: k, in: &$0)
                          }
                          if let c = copies, !c.isEmpty { document.setSelection(c) }
                      }) {
            Picker("Flip", selection: $horizontally) {
                Text("Left ↔ right").tag(true)
                Text("Top ↕ bottom").tag(false)
            }
            .pickerStyle(.segmented)
            Picker("About", selection: $pivot) {
                ForEach(VectorCommands.MirrorPivot.allCases) { Text($0.title(horizontally: horizontally)).tag($0) }
            }
            Toggle("Keep original (mirror copy)", isOn: $keepOriginal)
        }
    }
}
