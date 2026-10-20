import CADCore
import CAMCore
import SwiftUI

struct CircularArraySheet: View {
    enum CenterChoice: String, CaseIterable, Identifiable {
        case material, custom
        var id: String { rawValue }
    }

    @ObservedObject var document: KerfDocument
    @State private var count = 6
    @State private var evenly = true
    @State private var sweep = 360.0
    @State private var step = 30.0
    @State private var rotate = true
    @State private var centerChoice = CenterChoice.material
    @State private var center: Vec2

    init(document: KerfDocument) {
        self.document = document
        _center = State(initialValue: document.document.job.materialBounds.center)
    }

    private var stepValue: Double { evenly ? ArrayLayout.evenStep(count: count, sweepDegrees: sweep) : step }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        DrawingDialog(title: "Circular Array", action: "Create Copies", disabled: count < 2 || ids.isEmpty || stepValue == 0,
                      note: "\(count - 1) copies, \(RulerTicks.label((stepValue * 1000).rounded() / 1000))° apart (positive = counter-clockwise).",
                      perform: {
                          let c = centerChoice == .material ? document.document.job.materialBounds.center : center
                          let (n, s, r) = (count, stepValue, rotate)
                          var newIDs: [UUID] = []
                          document.perform("Circular Array") {
                              newIDs = VectorCommands.circularArray(ids, count: n, center: c, stepDegrees: s, rotateCopies: r, in: &$0)
                          }
                          if !newIDs.isEmpty { document.setSelection(ids + newIDs) }
                      }) {
            IntField("Items (total)", value: $count, range: 2...360)
            Toggle("Spread evenly", isOn: $evenly)
            if evenly {
                NumberField("Over angle", value: $sweep, unit: "°", help: "360° = full circle")
            } else {
                NumberField("Step angle", value: $step, unit: "°")
            }
            Toggle("Rotate copies", isOn: $rotate)
            Picker("Centre", selection: $centerChoice) {
                Text("Material centre").tag(CenterChoice.material)
                Text("Custom point").tag(CenterChoice.custom)
            }
            if centerChoice == .custom {
                LengthField("Centre X", value: $center.x, units: document.units)
                LengthField("Centre Y", value: $center.y, units: document.units)
            }
        }
    }
}

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
