import AppKit
import CADCore
import CAMCore

/// Overlays for the drawing tools: validator markers.
extension CanvasNSView {
    func drawDrawingOverlays(_ ctx: CGContext, _ doc: KerfDocument) {
        drawHighlightMarkers(ctx, doc)
    }

    private func drawHighlightMarkers(_ ctx: CGContext, _ doc: KerfDocument) {
        guard !doc.highlightMarkers.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(2)
        for p in doc.highlightMarkers {
            let v = viewport.toView(p)
            ctx.strokeEllipse(in: CGRect(x: v.x - 9, y: v.y - 9, width: 18, height: 18))
        }
        ctx.restoreGState()
    }
}
