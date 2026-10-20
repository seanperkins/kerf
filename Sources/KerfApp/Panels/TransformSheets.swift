import CADCore
import CAMCore
import SwiftUI

struct TrimBoundarySheet: View {
    @ObservedObject var document: KerfDocument
    @State private var keepInside = true

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let boundary = document.selectedShapes.first { $0.paths.contains(where: \.isClosed) }
        DrawingDialog(title: "Trim to Boundary", action: "Trim", disabled: boundary == nil,
                      note: boundary == nil ? "Select a closed boundary vector first."
                          : "Boundary: \(boundary!.name.isEmpty ? "first selected closed vector" : boundary!.name). "
                          + (ids.count > 1 ? "The other selected vectors are trimmed." : "Every editable vector is trimmed."),
                      perform: {
                          let k = keepInside
                          document.perform("Trim to Boundary") { VectorCommands.trimToBoundary(ids, keepInside: k, in: &$0) }
                      }) {
            Picker("Keep", selection: $keepInside) {
                Text("Inside").tag(true)
                Text("Outside").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }
}

struct DistortSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var envelope = false
    @State private var shearX = 15.0
    @State private var shearY = 0.0
    @State private var offsets = [Vec2](repeating: .zero, count: 4)

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let units = document.units
        DrawingDialog(title: "Shear / Distort", action: envelope ? "Distort" : "Shear", disabled: ids.isEmpty,
                      note: envelope ? "Moves the corners of the selection's bounding box and bends the vectors to follow (curves are refitted as lines and arcs; live text becomes curves)."
                          : "Slants the selection about its centre. Positive X slants the top to the right; positive Y raises the right side.",
                      perform: {
                          if envelope {
                              let o = offsets
                              document.perform("Distort") { VectorCommands.envelope(ids, offsets: o, in: &$0) }
                          } else {
                              let (x, y) = (shearX, shearY)
                              document.perform("Shear") { VectorCommands.shear(ids, xDegrees: x, yDegrees: y, in: &$0) }
                          }
                      }) {
            Picker("Mode", selection: $envelope) {
                Text("Shear").tag(false)
                Text("Envelope").tag(true)
            }
            .pickerStyle(.segmented)
            if envelope {
                ForEach(0..<4, id: \.self) { i in
                    let name = ["Lower left", "Lower right", "Upper right", "Upper left"][i]
                    LengthField("\(name) X", value: $offsets[i].x, units: units)
                    LengthField("\(name) Y", value: $offsets[i].y, units: units)
                }
            } else {
                NumberField("Shear X", value: $shearX, unit: "°")
                NumberField("Shear Y", value: $shearY, unit: "°")
            }
        }
    }
}

struct OpenOffsetSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var distance: Double
    @State private var side = VectorCommands.OpenOffsetSide.both

    init(document: KerfDocument) {
        self.document = document
        _distance = State(initialValue: document.units == .inch ? 0.125 : 3)
    }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let openCount = document.selectedShapes.reduce(0) { $0 + $1.paths.filter { !$0.isClosed }.count }
        DrawingDialog(title: "Offset Open Vectors", action: "Offset", disabled: openCount == 0 || distance <= 0,
                      note: openCount == 0 ? "Select open vectors (closed ones use Offset…)."
                          : "Left/right follow each vector's direction. The closed outline wraps the vector with round ends — the shape of a cut that wide.",
                      perform: {
                          let (d, s) = (distance, side)
                          var newIDs: [UUID] = []
                          document.perform("Offset Open Vectors") { newIDs = VectorCommands.offsetOpen(ids, distance: d, side: s, in: &$0) }
                          if !newIDs.isEmpty { document.setSelection(newIDs) }
                      }) {
            LengthField("Distance", value: $distance, units: document.units)
            Picker("Offset", selection: $side) {
                ForEach(VectorCommands.OpenOffsetSide.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}

struct StraightInlaySheet: View {
    @ObservedObject var document: KerfDocument
    @State private var diameter: Double
    @State private var clearance: Double
    @State private var mirrorPlug = true

    init(document: KerfDocument) {
        self.document = document
        _diameter = State(initialValue: document.units == .inch ? 0.125 : 3)
        _clearance = State(initialValue: document.units == .inch ? 0.005 : 0.1)
    }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let closed = document.selectedShapes.contains(where: \.isClosed)
        DrawingDialog(title: "Straight-Wall Inlay Offsets", action: "Create Pocket & Plug", disabled: !closed || diameter <= 0,
                      note: "Rounds every corner of the design to the end mill radius (so pocket and plug can both be cut), then makes an \"Inlay pocket\" vector (cut as a Pocket) and an \"Inlay plug\" vector beside it (cut with an outside Profile). The clearance is split between them. For V-bit inlays use Toolpaths › Inlay.",
                      perform: {
                          let (d, c, m) = (diameter, clearance, mirrorPlug)
                          var made: (UUID, UUID)?
                          document.perform("Inlay Offsets") { made = VectorCommands.straightInlay(ids, toolDiameter: d, clearance: c, mirrorPlug: m, in: &$0) }
                          if let (a, b) = made { document.setSelection([a, b]) }
                      }) {
            LengthField("End mill diameter", value: $diameter, units: document.units)
            LengthField("Clearance (total)", value: $clearance, units: document.units, help: "Gap between plug and pocket walls, both sides together")
            Toggle("Mirror the plug (glued face down)", isOn: $mirrorPlug)
        }
    }
}

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
