import CADCore
import CAMCore
import SwiftUI

/// How to type exact values on the canvas for the active tool.
struct QuickEntryHelp: View {
    var tool: CanvasTool

    var body: some View {
        if let text {
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String? {
        if [.circle, .polygon, .star].contains(tool) {
            return "Typed entry: with the pointer at the centre, type a radius (or radius<angle) and press Return."
        }
        if tool.isDragShape {
            return "Typed entry: with the pointer at the lower-left corner (or while dragging), type W,H and press Return."
        }
        if tool == .polyline || tool == .curve || tool == .arc {
            return "Typed entry: X,Y places the first point; then ΔX,ΔY, length<angle, or a length towards the pointer. Press Return after each value."
        }
        return nil
    }
}

/// Trim tool help and the trim-to-boundary command.
struct TrimToolOptions: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        Text("Click part of a vector to delete it up to the nearest crossings with other vectors. A vector that crosses nothing is deleted whole. Each click can be undone.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Button("Trim to Boundary…") { document.sheet = .drawing(.trimBoundary) }
            .disabled(document.selection.isEmpty)
            .help("Select a closed boundary first (and optionally the vectors to trim)")
    }
}

/// Arc tool options: click mode plus exact centre/radius/angle entry.
struct ArcToolOptions: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        let units = document.units
        Picker("Draw by", selection: $document.drawingOptions.arcFromCenter) {
            Text("3 points").tag(false)
            Text("Centre").tag(true)
        }
        .pickerStyle(.segmented)
        Text(document.drawingOptions.arcFromCenter
             ? "Click the centre, then the start point (sets the radius), then the end direction. The arc runs counter-clockwise."
             : "Click the start point, the end point, then a point the arc passes through.")
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Divider()
        Text("Exact arc").font(.subheadline.bold())
        LengthField("Centre X", value: $document.drawingOptions.exactCenter.x, units: units)
        LengthField("Centre Y", value: $document.drawingOptions.exactCenter.y, units: units)
        LengthField("Radius", value: $document.drawingOptions.arcRadius, units: units)
        NumberField("Start angle", value: $document.drawingOptions.arcStartAngle, unit: "°", help: "0° points right, counter-clockwise positive")
        NumberField("End angle", value: $document.drawingOptions.arcEndAngle, unit: "°")
        Button("Create Arc") {
            let o = document.drawingOptions
            if let p = ArcConstruction.centerAngles(center: o.exactCenter, radius: o.arcRadius,
                                                    startDegrees: o.arcStartAngle, endDegrees: o.arcEndAngle) {
                document.addShape(Shape(name: "Arc", layerID: document.currentLayerID, paths: [p]), actionName: "Draw Arc")
            }
        }
        .disabled(document.drawingOptions.arcRadius <= 0)
    }
}
