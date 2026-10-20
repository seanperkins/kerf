import Foundation

/// Accumulates Bézier pen input: click = corner node, click-drag = smooth node whose outgoing
/// handle follows the drag (the incoming handle mirrors it).
public struct PenPath: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public var point: Vec2
        /// Outgoing handle (absolute); nil for a corner node.
        public var handleOut: Vec2?

        public init(point: Vec2, handleOut: Vec2? = nil) { self.point = point; self.handleOut = handleOut }

        /// Incoming handle, mirrored through the node.
        public var handleIn: Vec2? { handleOut.map { point * 2 - $0 } }
    }

    public private(set) var nodes: [Node] = []

    public init(nodes: [Node] = []) { self.nodes = nodes }

    public var isEmpty: Bool { nodes.isEmpty }

    public mutating func addNode(_ p: Vec2) { nodes.append(Node(point: p)) }

    /// Sets the outgoing handle of the last node (during a drag). Tiny drags keep a corner.
    public mutating func dragLastHandle(to h: Vec2, minLength: Double = 1e-9) {
        guard let i = nodes.indices.last else { return }
        nodes[i].handleOut = h.distance(to: nodes[i].point) > minLength ? h : nil
    }

    public mutating func removeLast() { if !nodes.isEmpty { nodes.removeLast() } }

    /// True when `p` is within `tolerance` of the first node (click there closes the path).
    public func closes(at p: Vec2, tolerance: Double) -> Bool {
        nodes.count >= 2 && nodes[0].point.distance(to: p) <= tolerance
    }

    /// Builds the path. A segment is a cubic when either end node has a handle, else a line.
    /// Returns nil with fewer than 2 nodes (or fewer than 3 distinct for a closed path of lines).
    public func path(closed: Bool) -> Path? {
        guard nodes.count >= 2 else { return nil }
        var p = Path(start: nodes[0].point, isClosed: closed)
        func seg(_ a: Node, _ b: Node) -> PathSegment {
            if a.handleOut == nil && b.handleIn == nil { return .line(to: b.point) }
            return .cubic(to: b.point, control1: a.handleOut ?? a.point, control2: b.handleIn ?? b.point)
        }
        for i in 1..<nodes.count { p.segments.append(seg(nodes[i - 1], nodes[i])) }
        if closed {
            let curved = nodes.contains { $0.handleOut != nil }
            guard nodes.count >= 3 || curved else { return nil }
            p.segments.append(seg(nodes[nodes.count - 1], nodes[0]))
        }
        return p
    }
}
