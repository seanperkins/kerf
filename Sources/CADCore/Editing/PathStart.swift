import Foundation

extension PathNodes {
    /// Closed path re-ordered so it starts at anchor `k` (editable form). Toolpaths that honour
    /// vector start points begin cutting there. Nil for open paths or a bad index.
    public static func settingStart(_ path: Path, node k: Int) -> Path? {
        let e = editable(path)
        guard e.isClosed, e.segments.count >= 2, k >= 0, k < anchorCount(e) else { return nil }
        guard k > 0 else { return e }
        return Path(start: anchor(e, k), segments: Array(e.segments[k...] + e.segments[..<k]), isClosed: true)
    }
}

extension PathNodes {
    /// Segment `s` (editable form) replaced by a circular arc (as Béziers) through its start, its
    /// middle point and its end. A straight segment bulges to the left by a quarter of its length.
    public static func spanToArc(_ path: Path, segment s: Int) -> Path? {
        let e = editable(path)
        guard e.segments.indices.contains(s) else { return nil }
        let a = anchor(e, s), b = e.segments[s].end
        guard a.distance(to: b) > 1e-12 else { return nil }
        var mid = point(e, segment: s, t: 0.5)
        let chordMid = (a + b) / 2
        if VectorValidator.segmentDistance(mid, a, b) < a.distance(to: b) * 1e-3 {
            mid = chordMid + (b - a).perpendicular * 0.25
        }
        guard let arc = ArcConstruction.threePoint(start: a, end: b, through: mid),
              case .arc(_, let c, let cw) = arc.segments[0] else { return nil }
        var out = e
        out.segments.replaceSubrange(s...s, with: Flattening.arcToCubics(from: a, to: b, center: c, clockwise: cw))
        return out
    }
}

extension ShapeNodes {
    /// Shape with path `ref.path` starting at node `ref.node` (nil when not possible).
    public static func settingStart(_ shape: Shape, _ ref: NodeRef) -> Shape? {
        guard shape.paths.indices.contains(ref.path),
              let p = PathNodes.settingStart(shape.paths[ref.path], node: ref.node) else { return nil }
        var s = ShapeNodes.editable(shape)
        s.paths[ref.path] = p
        return s
    }
}
