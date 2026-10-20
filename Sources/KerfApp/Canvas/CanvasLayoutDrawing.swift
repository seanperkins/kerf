import AppKit
import CADCore
import CAMCore

/// Layout overlays on the design canvas: outlines of nesting sheets parked beside the material.
extension CanvasNSView {
    func drawLayoutOverlay(_ ctx: CGContext, _ doc: KerfDocument, _ vt: CGAffineTransform) {
        let d = doc.document
        guard NestSheets.hasSheets(d) else { return }
        let active = NestSheets.activeSheet(in: d)
        let material = d.job.materialBounds
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        for n in NestSheets.numbers(in: d) {
            let off = NestSheets.offset(ofSheet: n, in: d)
            let r = viewRect(Rect2(min: material.min + off, max: material.max + off))
            if n != active {
                ctx.saveGState()
                NSColor(srgbRed: 0.99, green: 0.97, blue: 0.93, alpha: 0.55).setFill()
                ctx.fill(r)
                ctx.setStrokeColor(NSColor(srgbRed: 0.55, green: 0.45, blue: 0.33, alpha: 1).cgColor)
                ctx.setLineWidth(1)
                ctx.setLineDash(phase: 0, lengths: [6, 4])
                ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
                ctx.restoreGState()
            }
            let label = n == active ? "Sheet \(n) — on the material" : "Sheet \(n) — parked (not cut)"
            (label as NSString).draw(at: CGPoint(x: r.minX, y: r.maxY + 4), withAttributes: attrs)
        }
    }
}
