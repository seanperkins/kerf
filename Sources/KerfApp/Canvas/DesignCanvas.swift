import AppKit
import CADCore
import SwiftUI

/// SwiftUI wrapper for the AppKit canvas.
struct DesignCanvas: NSViewRepresentable {
    @ObservedObject var document: KerfDocument
    /// Redraws when canvas colours change in Preferences.
    @ObservedObject private var preferences = PreferencesModel.shared

    func makeNSView(context: Context) -> CanvasNSView {
        let v = CanvasNSView()
        v.document = document
        return v
    }

    func updateNSView(_ v: CanvasNSView, context: Context) {
        v.document = document
        if document.activeTool != .polyline && document.activeTool != .curve { v.clickPoints = [] }
        if document.activeTool != .pen { v.pen = PenPath() }
        v.handle(document.canvasRequest)
        v.needsDisplay = true
    }
}

/// Vertical palette of drawing tools shown over the canvas' left edge.
struct ToolPalette: View {
    @ObservedObject var document: KerfDocument

    var body: some View {
        VStack(spacing: 2) {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    document.activeTool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 28, height: 26)
                        .background(document.activeTool == tool ? Color.accentColor.opacity(0.25) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        // A plain button only hit-tests what it draws, so without this the target was the glyph (11–17 pt).
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help(tool.titleWithKey)
                .accessibilityLabel(tool.title)
                .accessibilityAddTraits(document.activeTool == tool ? .isSelected : [])
                if tool == .nodeEdit { Divider().frame(width: 24) }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 1)
    }
}
