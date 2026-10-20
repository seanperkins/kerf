import CADCore
import CAMCore
import SwiftUI

/// Shows the dialog for a `DrawingSheet`.
struct DrawingSheetHost: View {
    @ObservedObject var document: KerfDocument
    var kind: DrawingSheet

    var body: some View {
        switch kind {
        case .dogbone: DogboneSheet(document: document)
        case .arrayLinear: RectangularArraySheet(document: document)
        case .validator: VectorValidatorSheet(document: document)
        case .mirror: MirrorSheet(document: document)
        case .trimBoundary: TrimBoundarySheet(document: document)
        case .filletChamfer: FilletChamferSheet(document: document)
        }
    }
}

/// Common dialog frame: title, form content, Cancel / action buttons.
struct DrawingDialog<Content: View>: View {
    var title: String
    var action: String
    var disabled = false
    var note: String?
    var perform: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            Form { content }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action) { perform(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(disabled)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: Fillet / chamfer

struct FilletChamferSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var chamfer = false
    @State private var size: Double

    init(document: KerfDocument) {
        self.document = document
        _size = State(initialValue: document.units == .inch ? 0.25 : 6)
    }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let nodes = document.activeTool == .nodeEdit ? document.nodeSelection : []
        DrawingDialog(title: "Fillet / Chamfer", action: chamfer ? "Chamfer" : "Fillet", disabled: size <= 0 || (ids.isEmpty && nodes.isEmpty),
                      note: (nodes.isEmpty ? "Every corner between two straight segments of the selected vectors is changed."
                             : "The \(nodes.count) selected node\(nodes.count == 1 ? "" : "s") are changed.")
                          + " Corners whose edges are too short are skipped.",
                      perform: {
                          let kind: CornerOps.Kind = chamfer ? .chamfer(distance: size) : .fillet(radius: size)
                          document.perform(chamfer ? "Chamfer" : "Fillet") {
                              VectorCommands.treatCorners(kind, shapes: ids, nodes: nodes, in: &$0)
                          }
                          document.nodeSelection = []
                      }) {
            Picker("Corner", selection: $chamfer) {
                Text("Fillet (round)").tag(false)
                Text("Chamfer (bevel)").tag(true)
            }
            .pickerStyle(.segmented)
            LengthField(chamfer ? "Distance" : "Radius", value: $size, units: document.units)
        }
    }
}

// MARK: Dog-bones

struct DogboneSheet: View {
    @ObservedObject var document: KerfDocument
    @State private var diameter: Double
    @State private var style = Dogbone.Style.dogbone
    @State private var side = Dogbone.CutSide.part
    @State private var maxAngle = 135.0

    init(document: KerfDocument) {
        self.document = document
        _diameter = State(initialValue: document.units == .inch ? 0.25 : 6)
    }

    var body: some View {
        let ids = document.selectedShapes.map(\.id)
        let count = document.project.document.shapes(ids: ids).reduce(0) {
            $0 + Dogbone.reliefCount($1.paths, radius: diameter / 2, style: style, side: side, maxAngle: maxAngle)
        }
        DrawingDialog(title: "Dog-bone Fillets", action: "Add Relief", disabled: count == 0 || diameter <= 0,
                      note: "Adds a round over-cut at each inside corner the cutter cannot reach, so square-cornered parts fit. \(count) corner\(count == 1 ? "" : "s") will be relieved.",
                      perform: {
                          let d = diameter, st = style, sd = side, a = maxAngle
                          document.perform("Dog-bone Fillets") {
                              VectorCommands.dogbone(ids, toolDiameter: d, style: st, side: sd, maxAngle: a, in: &$0)
                          }
                      }) {
            LengthField("Tool diameter", value: $diameter, units: document.units)
            Picker("Style", selection: $style) {
                Text("Dog-bone").tag(Dogbone.Style.dogbone)
                Text("T-bone (long edge)").tag(Dogbone.Style.tBoneLong)
                Text("T-bone (short edge)").tag(Dogbone.Style.tBoneShort)
            }
            Picker("Vectors are", selection: $side) {
                Text("Parts (cut outside)").tag(Dogbone.CutSide.part)
                Text("Openings (cut inside)").tag(Dogbone.CutSide.opening)
            }
            NumberField("Max corner angle", value: $maxAngle, unit: "°", help: "Corners wider than this are left alone")
        }
    }
}
