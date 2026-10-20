import AppKit
import CADCore
import CAMCore

/// Per-canvas state of the drawing extras.
struct CanvasDrawingState {
    /// Characters typed while a drawing tool is active (see `QuickEntry`).
    var quickEntry = ""
}

/// Trim tool, typed entry ("quick keys") while drawing.
extension CanvasNSView {
    /// Trim tool click: deletes the clicked span between intersections.
    func trimClick(_ p: Vec2, _ doc: KerfDocument) {
        let tol = pickTolerance
        var hit = false
        doc.perform("Trim") { hit = VectorCommands.trim(at: p, pickTolerance: tol, in: &$0) }
        if !hit { NSSound.beep() }
    }

    /// True when the drawing extras consumed the key.
    func handleDrawingToolKey(_ event: NSEvent, _ doc: KerfDocument) -> Bool {
        let tool = doc.activeTool
        guard tool.isDragShape || tool == .polyline || tool == .curve || tool == .arc else {
            drawingState.quickEntry = ""
            return false
        }
        let buffer = drawingState.quickEntry
        switch event.keyCode {
        case 36, 76:  // return, enter
            guard !buffer.isEmpty else { return false }
            applyQuickEntry(doc)
            return true
        case 51, 117:  // delete
            guard !buffer.isEmpty else { return false }
            drawingState.quickEntry.removeLast()
            return true
        case 53:  // escape
            guard !buffer.isEmpty else { return false }
            drawingState.quickEntry = ""
            return true
        default:
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let chars = event.characters, chars.count == 1, let c = chars.first,
                  QuickEntry.accepts(c, buffer: buffer) else { return false }
            drawingState.quickEntry.append(c)
            return true
        }
    }

    private func applyQuickEntry(_ doc: KerfDocument) {
        defer { drawingState.quickEntry = "" }
        guard let entry = QuickEntry.parse(drawingState.quickEntry) else { NSSound.beep(); return }
        let tool = doc.activeTool
        if tool.isDragShape {
            var anchor = hoverDoc ?? doc.document.job.materialBounds.center
            var direction = Vec2(1, 1)
            if case .draw(let s, let c) = drag {
                anchor = s
                direction = Vec2(c.x < s.x ? -1 : 1, c.y < s.y ? -1 : 1)
                drag = .none
            }
            guard let s = entry.shape(for: tool, anchor: anchor, direction: direction, options: doc.drawingOptions,
                                      layerID: doc.currentLayerID) else { NSSound.beep(); return }
            doc.addShape(s, actionName: "Draw \(tool.title)")
            return
        }
        // Click-built tools: the entry places the next point.
        let first = clickPoints.isEmpty
        guard let p = first ? entry.nextPoint(after: nil, cursor: hoverDoc) : entry.nextPoint(after: clickPoints.last, cursor: hoverDoc)
        else { NSSound.beep(); return }
        clickPoints.append(p)
        if tool == .arc, clickPoints.count >= 3 { finishClickShape() }
    }

    /// Typed entry shown next to the cursor.
    func drawQuickEntry(_ doc: KerfDocument) {
        let text = drawingState.quickEntry
        guard !text.isEmpty else { return }
        let anchor = hoverDoc.map { viewport.toView($0) } ?? Vec2(bounds.midX, bounds.midY)
        let hint: String
        switch QuickEntry.parse(text) {
        case .none: hint = ""
        case .some(.polar): hint = "  length<angle"
        case .some(.pair): hint = doc.activeTool.isDragShape ? "  W,H" : (clickPoints.isEmpty ? "  X,Y" : "  ΔX,ΔY")
        case .some(.one): hint = doc.activeTool.isDragShape ? "  size" : "  length"
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
        let s = (text + hint + "  ↩") as NSString
        let size = s.size(withAttributes: attrs)
        let r = CGRect(x: anchor.x + 14, y: anchor.y - size.height - 14, width: size.width + 10, height: size.height + 4)
        NSColor.systemBlue.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        s.draw(at: CGPoint(x: r.minX + 5, y: r.minY + 2), withAttributes: attrs)
    }
}
