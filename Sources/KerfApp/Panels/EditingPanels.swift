import CADCore
import CAMCore
import SwiftUI

/// Inspector while the node-edit tool is active: numeric node position and node commands.
struct NodeInspector: View {
    @ObservedObject var document: KerfDocument
    @State private var position = Vec2.zero

    private var single: NodeRef? { document.nodeSelection.count == 1 ? document.nodeSelection.first : nil }

    var body: some View {
        let units = document.units
        let nodes = document.nodeSelection
        InspectorSection(title: "Node Edit") {
            if document.selection.isEmpty {
                Text("Click a vector to show its nodes.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(nodes.isEmpty ? "No nodes selected" : "\(nodes.count) node\(nodes.count == 1 ? "" : "s") selected")
                    .font(.callout)
            }
            if single != nil {
                LengthField("X", value: $position.x, units: units)
                LengthField("Y", value: $position.y, units: units)
                Button("Move Node") {
                    guard let r = single, let cur = document.project.nodePosition(r) else { return }
                    let d = position - cur
                    document.perform("Move Node") { $0.moveNodes([r], by: d) }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Button("Delete") { document.deleteSelectedNodes() }
                    Button("Insert After") { document.insertNodesAfterSelection() }
                }
                GridRow {
                    Button("Smooth") { document.setSelectedNodes(smooth: true) }
                    Button("Corner") { document.setSelectedNodes(smooth: false) }
                }
                GridRow {
                    Button("To Curve") { document.convertSegmentsAfterSelectedNodes(toCurve: true) }
                        .help("Make the segment after each selected node a Bézier curve")
                    Button("To Line") { document.convertSegmentsAfterSelectedNodes(toCurve: false) }
                        .help("Make the segment after each selected node a straight line")
                }
                GridRow {
                    Button("Break Here") { document.breakAtSelectedNode() }.disabled(single == nil)
                }
            }
            .disabled(nodes.isEmpty)
            Text("Drag nodes or handles (Option breaks a smooth node). Shift-click adds nodes; drag on empty space to box-select. Double-click a segment to insert a node. Delete removes nodes; arrows nudge.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Snap to grid", isOn: $document.snapToGrid)
            Toggle("Snap to objects", isOn: $document.snapToObjects)
            Button("Done") { document.activeTool = .select }
        }
        .onAppear(perform: refresh)
        .onChange(of: document.nodeSelection) { _, _ in refresh() }
        .onChange(of: document.project) { _, _ in refresh() }
    }

    private func refresh() {
        if let r = single, let p = document.project.nodePosition(r) { position = p }
    }
}

/// Numeric creation of the active drag tool's shape (exact centre and size).
struct ExactShapeSection: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        let units = document.units
        let tool = document.activeTool
        let radial = [.circle, .polygon, .star].contains(tool)
        InspectorSection(title: "Exact Size") {
            LengthField("Centre X", value: $document.drawingOptions.exactCenter.x, units: units)
            LengthField("Centre Y", value: $document.drawingOptions.exactCenter.y, units: units)
            LengthField(radial ? "Diameter" : "Width", value: $document.drawingOptions.exactWidth, units: units)
            if !radial {
                LengthField("Height", value: $document.drawingOptions.exactHeight, units: units)
            }
            HStack {
                Button("Create \(tool.title)") {
                    let o = document.drawingOptions
                    if let s = DrawingTools.exactShape(for: tool, center: o.exactCenter, width: o.exactWidth, height: o.exactHeight,
                                                       options: o, layerID: document.currentLayerID) {
                        document.addShape(s, actionName: "Draw \(tool.title)")
                    }
                }
                Button("Centre on Material") {
                    document.drawingOptions.exactCenter = document.document.job.materialBounds.center
                }
            }
        }
    }
}

/// Relative move and percentage scale of the selection.
struct MoveScaleFields: View {
    @ObservedObject var document: KerfDocument
    @State private var delta = Vec2.zero
    @State private var scaleX = 100.0
    @State private var scaleY = 100.0

    var body: some View {
        let units = document.units
        HStack {
            LengthField("Move X", value: $delta.x, units: units)
        }
        HStack {
            LengthField("Move Y", value: $delta.y, units: units)
            Button("Move") { document.translateSelection(by: delta, actionName: "Move") }
        }
        NumberField("Scale X", value: $scaleX, unit: "%")
        HStack {
            NumberField("Scale Y", value: $scaleY, unit: "%")
            Button("Scale") {
                guard scaleX != 0, scaleY != 0 else { return }
                let c = document.project.bounds(of: document.selection).center
                document.transformSelection(by: .scale(scaleX / 100, scaleY / 100, about: c), actionName: "Scale")
            }
        }
    }
}
