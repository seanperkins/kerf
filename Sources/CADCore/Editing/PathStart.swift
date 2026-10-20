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
