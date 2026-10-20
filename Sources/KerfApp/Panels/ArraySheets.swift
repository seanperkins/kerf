import CADCore
import CAMCore
import SwiftUI

struct RectangularArraySheet: View {
    @ObservedObject var document: KerfDocument
    @State private var rows = 2
    @State private var columns = 3
    @State private var x: Double
    @State private var y: Double
    @State private var spacing = ArrayLayout.Spacing.gap

    init(document: KerfDocument) {
        self.document = document
        let g = document.units == .inch ? 0.25 : 6
        _x = State(initialValue: g)
        _y = State(initialValue: g)
    }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let size = document.project.bounds(of: document.selection).size
        let u = document.units.abbreviation
        DrawingDialog(title: "Rectangular Array", action: "Create Copies", disabled: rows * columns < 2 || ids.isEmpty,
                      note: "Selection is \(RulerTicks.label(size.x)) × \(RulerTicks.label(size.y)) \(u). Columns run right and rows up; use negative distances to go left or down. \(max(0, rows * columns - 1)) copies.",
                      perform: {
                          let (r, c, dx, dy, sp) = (rows, columns, x, y, spacing)
                          var newIDs: [UUID] = []
                          document.perform("Rectangular Array") {
                              newIDs = VectorCommands.rectangularArray(ids, rows: r, columns: c, x: dx, y: dy, spacing: sp, in: &$0)
                          }
                          if !newIDs.isEmpty { document.setSelection(ids + newIDs) }
                      }) {
            IntField("Rows", value: $rows, range: 1...500)
            IntField("Columns", value: $columns, range: 1...500)
            Picker("Spacing", selection: $spacing) {
                Text("Gap between copies").tag(ArrayLayout.Spacing.gap)
                Text("Offset (centre to centre)").tag(ArrayLayout.Spacing.offset)
            }
            LengthField(spacing == .gap ? "X gap" : "X offset", value: $x, units: document.units)
            LengthField(spacing == .gap ? "Y gap" : "Y offset", value: $y, units: document.units)
        }
    }
}
