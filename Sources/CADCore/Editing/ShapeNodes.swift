import Foundation

/// Identifies one anchor of one path of a shape (indices refer to the editable form).
public struct NodeRef: Hashable, Codable, Sendable {
    public var shapeID: UUID
    public var path: Int
    public var node: Int

    public init(shapeID: UUID, path: Int, node: Int) {
        self.shapeID = shapeID; self.path = path; self.node = node
    }
}

/// Identifies one segment of one path of a shape (editable form).
public struct SegmentRef: Hashable, Codable, Sendable {
    public var shapeID: UUID
    public var path: Int
    public var segment: Int

    public init(shapeID: UUID, path: Int, segment: Int) {
        self.shapeID = shapeID; self.path = path; self.segment = segment
    }
}

/// Shape-level wrappers over `PathNodes`. Every edit returns a shape whose paths are all in
/// editable form; parametric provenance (rectangle, circle…) is dropped because the result is
/// no longer that primitive.
public enum ShapeNodes {
    /// The shape with every path converted to editable form (geometry unchanged).
    public static func editable(_ s: Shape) -> Shape {
        var c = s
        c.paths = s.paths.map(PathNodes.editable)
        return c
    }

    /// All anchors with their positions, in path/anchor order.
    public static func nodes(of s: Shape) -> [(ref: NodeRef, point: Vec2)] {
        let e = editable(s)
        return e.paths.enumerated().flatMap { pi, p in
            PathNodes.anchors(p).enumerated().map { (NodeRef(shapeID: s.id, path: pi, node: $0.offset), $0.element) }
        }
    }

    /// Nearest anchor within `tolerance` of `q`.
    public static func hitNode(_ s: Shape, at q: Vec2, tolerance: Double) -> NodeRef? {
        nodes(of: s).filter { $0.point.distance(to: q) <= tolerance }
            .min { $0.point.distance(to: q) < $1.point.distance(to: q) }?.ref
    }

    /// Nearest Bézier handle within `tolerance` of `q`.
    public static func hitHandle(_ s: Shape, at q: Vec2, tolerance: Double) -> (NodeRef, PathNodes.Handle)? {
        let e = editable(s)
        var best: (NodeRef, PathNodes.Handle, Double)?
        for (pi, p) in e.paths.enumerated() {
            for k in 0..<PathNodes.anchorCount(p) {
                for h in [PathNodes.Handle.incoming, .outgoing] {
                    guard let v = PathNodes.handle(p, k, h) else { continue }
                    let d = v.distance(to: q)
                    if d <= tolerance, d < (best?.2 ?? .infinity) { best = (NodeRef(shapeID: s.id, path: pi, node: k), h, d) }
                }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Nearest segment within `tolerance` of `q`, with the parameter of the closest point.
    public static func hitSegment(_ s: Shape, at q: Vec2, tolerance: Double) -> (SegmentRef, t: Double)? {
        let e = editable(s)
        var best: (SegmentRef, Double, Double)?
        for (pi, p) in e.paths.enumerated() {
            guard let h = PathNodes.nearestSegment(p, to: q), h.distance <= tolerance else { continue }
            if h.distance < (best?.2 ?? .infinity) { best = (SegmentRef(shapeID: s.id, path: pi, segment: h.segment), h.t, h.distance) }
        }
        return best.map { ($0.0, $0.1) }
    }

    // MARK: Edits

    /// Moves several anchors of `s` by `delta` (anchors of other shapes are ignored).
    public static func moveNodes(_ s: Shape, _ refs: Set<NodeRef>, by delta: Vec2) -> Shape {
        var e = editable(s)
        for r in refs where r.shapeID == s.id && e.paths.indices.contains(r.path) {
            let p = e.paths[r.path]
            guard r.node < PathNodes.anchorCount(p) else { continue }
            e.paths[r.path] = PathNodes.moveAnchor(p, r.node, to: PathNodes.anchor(p, r.node) + delta)
        }
        return touched(e)
    }

    public static func moveNode(_ s: Shape, _ r: NodeRef, to point: Vec2) -> Shape {
        edit(s, r.path) { PathNodes.moveAnchor($0, r.node, to: point) }
    }

    public static func moveHandle(_ s: Shape, _ r: NodeRef, _ h: PathNodes.Handle, to point: Vec2, keepSmooth: Bool) -> Shape {
        edit(s, r.path) { PathNodes.moveHandle($0, r.node, h, to: point, keepSmooth: keepSmooth) }
    }

    public static func insertNode(_ s: Shape, _ r: SegmentRef, t: Double) -> Shape {
        edit(s, r.path) { PathNodes.insertAnchor($0, segment: r.segment, t: t) }
    }

    /// Deletes anchors; returns nil when any affected path would become degenerate.
    /// Higher indices are removed first so lower indices stay valid.
    public static func deleteNodes(_ s: Shape, _ refs: Set<NodeRef>) -> Shape? {
        var e = editable(s)
        let mine = refs.filter { $0.shapeID == s.id }.sorted { ($0.path, $0.node) > ($1.path, $1.node) }
        for r in mine {
            guard e.paths.indices.contains(r.path), let p = PathNodes.deleteAnchor(e.paths[r.path], r.node) else { return nil }
            e.paths[r.path] = p
        }
        return touched(e)
    }

    public static func convertSegment(_ s: Shape, _ r: SegmentRef, toCurve: Bool) -> Shape {
        edit(s, r.path) { PathNodes.convertSegment($0, r.segment, toCurve: toCurve) }
    }

    /// Converts both segments around each node to lines (corner) or smooth curves.
    public static func setNodes(_ s: Shape, _ refs: Set<NodeRef>, smooth: Bool) -> Shape {
        var e = editable(s)
        for r in refs where r.shapeID == s.id && e.paths.indices.contains(r.path) {
            var p = e.paths[r.path]
            if smooth {
                p = PathNodes.makeSmooth(p, r.node)
            } else {
                for seg in [PathNodes.incomingSegment(p, r.node), PathNodes.outgoingSegment(p, r.node)].compactMap({ $0 }) {
                    p = PathNodes.convertSegment(p, seg, toCurve: false)
                }
            }
            e.paths[r.path] = p
        }
        return touched(e)
    }

    /// Splits an open or closed path at a node: a closed path opens there; an open path breaks
    /// into two paths (the second path is appended to the shape).
    public static func breakAt(_ s: Shape, _ r: NodeRef) -> Shape {
        var e = editable(s)
        guard e.paths.indices.contains(r.path) else { return s }
        let p = e.paths[r.path]
        let n = PathNodes.anchorCount(p)
        guard r.node < n, !p.segments.isEmpty else { return s }
        if p.isClosed {
            // Rotate so the path starts and ends at the node, then open it.
            let segs = Array(p.segments[r.node...]) + Array(p.segments[..<r.node])
            e.paths[r.path] = Path(start: PathNodes.anchor(p, r.node), segments: segs, isClosed: false)
        } else {
            guard r.node > 0, r.node < n - 1 else { return s }
            let first = Path(start: p.start, segments: Array(p.segments[..<r.node]), isClosed: false)
            let second = Path(start: PathNodes.anchor(p, r.node), segments: Array(p.segments[r.node...]), isClosed: false)
            e.paths[r.path] = first
            e.paths.insert(second, at: r.path + 1)
        }
        return touched(e)
    }

    // MARK: Helpers

    private static func edit(_ s: Shape, _ pathIndex: Int, _ f: (Path) -> Path) -> Shape {
        var e = editable(s)
        guard e.paths.indices.contains(pathIndex) else { return s }
        e.paths[pathIndex] = f(e.paths[pathIndex])
        return touched(e)
    }

    private static func touched(_ s: Shape) -> Shape {
        var c = s
        switch c.origin {
        case .imported, .drawn, .derived: break
        default: c.origin = .drawn
        }
        return c
    }
}
