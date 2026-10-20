import AppKit
import CADCore
import CAMCore

/// The 2D design canvas: material, grid, rulers, shapes, toolpath overlay, selection, drawing
/// tools. Unflipped (Y up) so document and view axes agree.
final class CanvasNSView: NSView, NSUserInterfaceValidations {
    weak var document: KerfDocument? {
        didSet {
            if document !== oldValue {
                didInitialFit = false; userAdjustedView = false
                flatCache.removeAll(); pathCache.removeAll()
            }
        }
    }

    var viewport = CanvasViewport() {
        didSet { if !isAutoFitting { userAdjustedView = true } }
    }
    /// Until the user pans/zooms, the view keeps the material fitted as the window resizes.
    private var userAdjustedView = false
    private var isAutoFitting = false
    static let rulerSize: CGFloat = 20

    // Interaction state.
    enum DragState {
        case none
        case pending(startView: Vec2, hitID: UUID?, extend: Bool)
        case marquee(startView: Vec2, currentView: Vec2, extend: Bool)
        case move(startDoc: Vec2, currentDoc: Vec2)
        case pan(lastView: Vec2)
        case draw(startDoc: Vec2, currentDoc: Vec2)
    }
    var drag: DragState = .none
    /// Points clicked so far for polyline/curve tools.
    var clickPoints: [Vec2] = []
    var hoverDoc: Vec2?
    var spaceHeld = false
    private var didInitialFit = false
    private var lastRequestSerial = 0
    private var trackingArea: NSTrackingArea?

    // Caches keyed by shape id (entries are reused while the shape is unchanged).
    private var flatCache: [UUID: FlatShape] = [:]
    private var pathCache: [UUID: (shape: Shape, path: CGPath)] = [:]
    private var toolpathCache: [UUID: (result: [Toolpath], job: JobSetup, cuts: CGPath, rapids: CGPath)] = [:]

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if (!didInitialFit || !userAdjustedView), bounds.width > 100, bounds.height > 100 {
            didInitialFit = true
            isAutoFitting = true
            fitMaterial()
            isAutoFitting = false
        }
    }

    // MARK: Requests from the document

    func handle(_ request: CanvasRequest) {
        guard request.serial != lastRequestSerial else { return }
        lastRequestSerial = request.serial
        switch request.kind {
        case .fit:
            isAutoFitting = true
            fitMaterial()
            isAutoFitting = false
            userAdjustedView = false
        case .fitSelection:
            if let doc = document, !doc.selection.isEmpty { fit(doc.project.bounds(of: doc.selection)) } else { fitMaterial() }
        case .zoomIn: zoom(by: 1.25, aboutView: center)
        case .zoomOut: zoom(by: 0.8, aboutView: center)
        }
    }

    private var center: Vec2 { Vec2(Double(bounds.midX), Double(bounds.midY)) }

    /// Area available for content (inside the rulers).
    var contentSize: Vec2 {
        Vec2(Double(bounds.width - Self.rulerSize), Double(bounds.height - Self.rulerSize))
    }

    func fitMaterial() {
        guard let doc = document else { return }
        fit(doc.document.job.materialBounds.union(doc.document.bounds))
    }

    func fit(_ rect: Rect2) {
        var vp = viewport
        vp.fit(rect, viewSize: contentSize)
        // Shift right of the vertical ruler (the horizontal ruler sits at the top).
        vp.offset += Vec2(Double(Self.rulerSize), 0)
        viewport = vp
        needsDisplay = true
    }

    func zoom(by factor: Double, aboutView p: Vec2) {
        viewport.zoom(by: factor, about: p)
        needsDisplay = true
    }

    // MARK: Caches

    var tolerance: Double { document?.units == .millimeter ? 0.02 : 0.001 }

    func flatShapes(_ shapes: [Shape]) -> [FlatShape] {
        shapes.map { s in
            if let c = flatCache[s.id], c.shape == s { return c }
            let f = FlatShape(s, tolerance: tolerance)
            flatCache[s.id] = f
            return f
        }
    }

    func cgPath(_ s: Shape) -> CGPath {
        if let c = pathCache[s.id], c.shape == s { return c.path }
        let p = CanvasPaths.cgPath(for: s)
        pathCache[s.id] = (s, p)
        return p
    }

    func toolpathGeometry(_ opID: UUID, _ tps: [Toolpath], job: JobSetup) -> (cuts: CGPath, rapids: CGPath) {
        if let c = toolpathCache[opID], c.result == tps, c.job == job { return (c.cuts, c.rapids) }
        let coords = MachineCoordinates(job: job)
        let cuts = CGMutablePath(), rapids = CGMutablePath()
        for tp in tps {
            let g = CanvasPaths.toolpathPaths(tp, coords: coords)
            cuts.addPath(g.cuts); rapids.addPath(g.rapids)
        }
        toolpathCache[opID] = (tps, job, cuts, rapids)
        return (cuts, rapids)
    }

    func pruneCaches() {
        guard let doc = document else { return }
        let ids = Set(doc.project.document.shapes.map(\.id))
        flatCache = flatCache.filter { ids.contains($0.key) }
        pathCache = pathCache.filter { ids.contains($0.key) }
        toolpathCache = toolpathCache.filter { doc.results[$0.key] != nil }
    }

    /// Shapes that can be picked (visible, unlocked layers; unlocked shapes).
    var pickableShapes: [FlatShape] {
        guard let doc = document else { return [] }
        return flatShapes(doc.project.document.shapes.filter { doc.project.isEditable($0) })
    }

    // MARK: Coordinates

    func viewPoint(_ event: NSEvent) -> Vec2 { Vec2(convert(event.locationInWindow, from: nil)) }

    func docPoint(_ event: NSEvent, snapped: Bool = true) -> Vec2 {
        let p = viewport.toDocument(viewPoint(event))
        guard snapped, let doc = document, doc.snapToGrid, !event.modifierFlags.contains(.command) else { return p }
        return Snapping.snap(p, grid: doc.document.gridSpacing)
    }

    /// Snaps a translation so grid-aligned geometry stays on the grid.
    func snappedDelta(_ d: Vec2) -> Vec2 {
        guard let doc = document, doc.snapToGrid else { return d }
        return Snapping.snap(d, grid: doc.document.gridSpacing)
    }
}
