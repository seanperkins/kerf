import AppKit
import CADCore
import CAMCore

/// Mouse, keyboard and responder-chain (Edit menu) handling for the canvas.
extension CanvasNSView {
    private var dragThreshold: Double { 3 }
    private var pickTolerance: Double { viewport.documentLength(5) }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let doc = document else { return }
        let v = viewPoint(event)
        if spaceHeld || event.modifierFlags.contains(.option) && doc.activeTool == .select {
            drag = .pan(lastView: v); NSCursor.closedHand.set(); return
        }
        switch doc.activeTool {
        case .select:
            let p = docPoint(event, snapped: false)
            let hit = HitTesting.pick(at: p, in: pickableShapes, tolerance: pickTolerance)
            drag = .pending(startView: v, hitID: hit, extend: event.modifierFlags.contains(.shift))
        case .polyline, .curve:
            let p = docPoint(event)
            if event.clickCount >= 2 { finishClickShape(); return }
            if clickPoints.count >= 2, let first = clickPoints.first,
               viewport.toView(first).distance(to: v) < 8 {
                clickPoints.append(first); finishClickShape(); return
            }
            clickPoints.append(p)
        case .text:
            placeText(at: docPoint(event))
        default:
            let p = docPoint(event)
            drag = .draw(startDoc: p, currentDoc: p)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = document else { return }
        let v = viewPoint(event)
        updateHover(event)
        switch drag {
        case .pan(let last):
            viewport.pan(by: v - last)
            drag = .pan(lastView: v)
        case .pending(let start, let hit, let extend):
            guard start.distance(to: v) >= dragThreshold else { return }
            if let id = hit {
                if !doc.selection.contains(id) { doc.select(id, extending: extend) }
                let startDoc = viewport.toDocument(start)
                drag = .move(startDoc: startDoc, currentDoc: viewport.toDocument(v))
            } else {
                drag = .marquee(startView: start, currentView: v, extend: extend)
            }
        case .move(let s, _):
            drag = .move(startDoc: s, currentDoc: viewport.toDocument(v))
        case .marquee(let s, _, let extend):
            drag = .marquee(startView: s, currentView: v, extend: extend)
        case .draw(let s, _):
            drag = .draw(startDoc: s, currentDoc: docPoint(event))
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let doc = document else { drag = .none; return }
        switch drag {
        case .pending(_, let hit, let extend):
            if let id = hit { doc.select(id, extending: extend) } else if !extend { doc.clearSelection() }
        case .move(let s, let c):
            doc.translateSelection(by: snappedDelta(c - s))
        case .marquee(let a, let b, let extend):
            let rect = Rect2(points: [viewport.toDocument(a), viewport.toDocument(b)])
            let ids = HitTesting.select(in: rect, candidates: pickableShapes, crossing: b.x < a.x)
            if extend { doc.addToSelection(ids) } else { doc.setSelection(ids) }
        case .draw(let a, let b):
            var opts = doc.drawingOptions
            opts.constrain = event.modifierFlags.contains(.shift)
            if let s = DrawingTools.shape(for: doc.activeTool, from: a, to: b, options: opts, layerID: doc.currentLayerID) {
                doc.addShape(s, actionName: "Draw \(doc.activeTool.title)")
            }
        case .pan:
            NSCursor.arrow.set()
        case .none:
            break
        }
        drag = .none
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let doc = document else { return }
        let p = docPoint(event, snapped: false)
        if let hit = HitTesting.pick(at: p, in: pickableShapes, tolerance: pickTolerance), !doc.selection.contains(hit) {
            doc.select(hit, extending: false)
        }
        NSMenu.popUpContextMenu(contextMenu(doc), with: event, for: self)
    }

    override func otherMouseDown(with event: NSEvent) { drag = .pan(lastView: viewPoint(event)) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { drag = .none }

    override func mouseMoved(with event: NSEvent) {
        updateHover(event)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverDoc = nil
        document?.cursorPosition = nil
        needsDisplay = true
    }

    private func updateHover(_ event: NSEvent) {
        let p = docPoint(event, snapped: !clickPoints.isEmpty || document?.activeTool != .select)
        hoverDoc = p
        document?.cursorPosition = p
    }

    override func scrollWheel(with event: NSEvent) {
        let v = viewPoint(event)
        if event.modifierFlags.contains(.command) || !event.hasPreciseScrollingDeltas {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            zoom(by: exp(Double(dy)), aboutView: v)
        } else {
            viewport.pan(by: Vec2(Double(event.scrollingDeltaX), Double(-event.scrollingDeltaY)))
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + Double(event.magnification), aboutView: viewPoint(event))
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let doc = document else { return super.keyDown(with: event) }
        let step = doc.document.gridSpacing * (event.modifierFlags.contains(.shift) ? 10 : 1)
        switch event.keyCode {
        case 49: // space
            spaceHeld = true; NSCursor.openHand.set()
        case 51, 117: // delete, forward delete
            doc.deleteSelection()
        case 53: // escape
            if !clickPoints.isEmpty { clickPoints = [] } else if doc.activeTool != .select { doc.activeTool = .select } else { doc.clearSelection() }
        case 36, 76: // return, enter
            finishClickShape()
        case 123: doc.translateSelection(by: Vec2(-step, 0), actionName: "Nudge")
        case 124: doc.translateSelection(by: Vec2(step, 0), actionName: "Nudge")
        case 125: doc.translateSelection(by: Vec2(0, -step), actionName: "Nudge")
        case 126: doc.translateSelection(by: Vec2(0, step), actionName: "Nudge")
        default:
            switch event.charactersIgnoringModifiers {
            case "f" where event.modifierFlags.intersection([.command, .control, .option]).isEmpty:
                fitMaterial()
            default:
                super.keyDown(with: event)
            }
        }
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false; NSCursor.arrow.set() } else { super.keyUp(with: event) }
    }

    // MARK: Click-built shapes

    func finishClickShape() {
        guard let doc = document else { return }
        defer { clickPoints = []; needsDisplay = true }
        let tol = viewport.documentLength(8)
        let shape = doc.activeTool == .curve
            ? DrawingTools.smoothCurve(points: clickPoints, closeTolerance: tol, layerID: doc.currentLayerID)
            : DrawingTools.polyline(points: clickPoints, closeTolerance: tol, layerID: doc.currentLayerID)
        if let s = shape { doc.addShape(s, actionName: "Draw \(doc.activeTool.title)") }
    }

    private func placeText(at p: Vec2) {
        guard let doc = document else { return }
        let o = doc.drawingOptions
        guard !o.text.isEmpty else { return }
        do {
            let paths = try TextOutliner().outlines(for: o.text, fontName: o.fontName, size: o.fontSize, origin: p)
            guard !paths.isEmpty else { return }
            doc.addShape(Shape(name: o.text, layerID: doc.currentLayerID, paths: paths,
                               origin: .text(o.text, fontName: o.fontName, size: o.fontSize)), actionName: "Add Text")
        } catch {
            doc.alert = AlertMessage(title: "Text", message: ImportService.describe(error))
        }
    }

    // MARK: Context menu

    private func contextMenu(_ doc: KerfDocument) -> NSMenu {
        let m = NSMenu()
        func item(_ title: String, _ action: Selector, enabled: Bool = true) {
            let i = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        let has = !doc.selection.isEmpty
        item("Cut", #selector(cut(_:)), enabled: has)
        item("Copy", #selector(copy(_:)), enabled: has)
        item("Paste", #selector(paste(_:)))
        item("Duplicate", #selector(duplicateShapes(_:)), enabled: has)
        item("Delete", #selector(delete(_:)), enabled: has)
        m.addItem(.separator())
        item("Zoom to Selection", #selector(zoomToSelection(_:)), enabled: has)
        item("Zoom to Material", #selector(zoomToMaterial(_:)))
        return m
    }

    @objc func duplicateShapes(_ sender: Any?) { document?.duplicateSelection() }
    @objc func zoomToSelection(_ sender: Any?) { document?.requestCanvas(.fitSelection) }
    @objc func zoomToMaterial(_ sender: Any?) { fitMaterial() }

    // MARK: Edit menu (responder chain)

    static let shapesPasteboardType = NSPasteboard.PasteboardType("com.seanperkins.kerf.shapes")

    override func selectAll(_ sender: Any?) { document?.selectAll(); needsDisplay = true }
    @objc func delete(_ sender: Any?) { document?.deleteSelection() }

    @objc func copy(_ sender: Any?) {
        guard let doc = document, !doc.selection.isEmpty,
              let data = try? JSONEncoder().encode(doc.selectedShapes) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: Self.shapesPasteboardType)
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        document?.deleteSelection()
    }

    @objc func paste(_ sender: Any?) {
        guard let doc = document, let data = NSPasteboard.general.data(forType: Self.shapesPasteboardType),
              let shapes = try? JSONDecoder().decode([Shape].self, from: data), !shapes.isEmpty else { return }
        let g = doc.document.gridSpacing
        let existing = Set(doc.document.shapes.map(\.id))
        let layer = doc.currentLayerID
        let pasted: [Shape] = shapes.map { s in
            var c = existingOffset(s, existing.contains(s.id) ? Vec2(g, -g) : .zero)
            c.id = UUID()
            if doc.document.layer(id: c.layerID) == nil { c.layerID = layer }
            return c
        }
        doc.perform("Paste") { p in pasted.forEach { p.document.add($0) } }
        doc.setSelection(pasted.map(\.id))
    }

    private func existingOffset(_ s: Shape, _ d: Vec2) -> Shape { d == .zero ? s : s.transformed(.translation(d)) }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let doc = document else { return false }
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)), #selector(duplicateShapes(_:)):
            return !doc.selection.isEmpty
        case #selector(paste(_:)):
            return NSPasteboard.general.data(forType: Self.shapesPasteboardType) != nil
        default:
            return true
        }
    }
}
