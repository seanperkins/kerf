import Foundation

/// Symmetric ("mirror mode") node editing: a node or handle moved on one side of a shape moves
/// its mirror partner the same way, reflected about the shape's bounding-box centre lines.
public enum NodeMirrorMode: String, CaseIterable, Codable, Hashable, Sendable {
    case off
    /// About the vertical centre line (left half mirrors the right half).
    case leftRight
    /// About the horizontal centre line.
    case topBottom
    /// Both centre lines (and the centre point).
    case both

    public var title: String {
        switch self {
        case .off: return "Off"
        case .leftRight: return "Left – Right"
        case .topBottom: return "Top – Bottom"
        case .both: return "Both"
        }
    }

    /// Sign pairs of the reflections used: (-1, 1) flips X, (1, -1) flips Y.
    var reflections: [Vec2] {
        switch self {
        case .off: return []
        case .leftRight: return [Vec2(-1, 1)]
        case .topBottom: return [Vec2(1, -1)]
        case .both: return [Vec2(-1, 1), Vec2(1, -1), Vec2(-1, -1)]
        }
    }

    /// Next mode in the cycle (the canvas M key).
    public var next: NodeMirrorMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public enum NodeMirror {
    static func scale(_ v: Vec2, _ s: Vec2) -> Vec2 { Vec2(v.x * s.x, v.y * s.y) }

    static func reflect(_ p: Vec2, about c: Vec2, _ s: Vec2) -> Vec2 { c + scale(p - c, s) }

    /// Matching tolerance: a small fraction of the shape size (hand-drawn symmetry is rarely exact).
    static func matchTolerance(_ box: Rect2, _ given: Double?) -> Double {
        given ?? max(box.width, box.height, 1e-9) * 1e-4 + 1e-9
    }

    /// Mirror centre used for `s` (its bounding-box centre).
    public static func center(of s: Shape) -> Vec2 { s.bounds().center }

    /// The anchor of `s` nearest to `point` within `tolerance` (editable-form indices).
    static func node(in e: Shape, near point: Vec2, tolerance: Double) -> NodeRef? {
        var best: (NodeRef, Double)?
        for (pi, p) in e.paths.enumerated() {
            for k in 0..<PathNodes.anchorCount(p) {
                let d = PathNodes.anchor(p, k).distance(to: point)
                if d <= tolerance, d < (best?.1 ?? .infinity) { best = (NodeRef(shapeID: e.id, path: pi, node: k), d) }
            }
        }
        return best?.0
    }

    /// Mirror partners of `r` (one per reflection of `mode`; may be `r` itself for a node on a centre line).
    public static func partners(of r: NodeRef, in s: Shape, mode: NodeMirrorMode, tolerance: Double? = nil) -> [(NodeRef, Vec2)] {
        let e = ShapeNodes.editable(s)
        let box = e.bounds(), c = box.center, tol = matchTolerance(box, tolerance)
        guard e.paths.indices.contains(r.path), r.node < PathNodes.anchorCount(e.paths[r.path]) else { return [] }
        let pos = PathNodes.anchor(e.paths[r.path], r.node)
        return mode.reflections.compactMap { sign in node(in: e, near: reflect(pos, about: c, sign), tolerance: tol).map { ($0, sign) } }
    }

    /// Moves the selected anchors of `s` by `delta` and their mirror partners by the reflected
    /// delta. A node lying on a centre line only slides along that line, so the shape stays
    /// symmetric. With `.off` this is `ShapeNodes.moveNodes`.
    public static func moveNodes(_ s: Shape, _ refs: Set<NodeRef>, by delta: Vec2, mode: NodeMirrorMode,
                                 tolerance: Double? = nil) -> Shape {
        guard mode != .off else { return ShapeNodes.moveNodes(s, refs, by: delta) }
        var e = ShapeNodes.editable(s)
        let mine = refs.filter { $0.shapeID == s.id && e.paths.indices.contains($0.path)
            && $0.node < PathNodes.anchorCount(e.paths[$0.path]) }
        var moves: [NodeRef: Vec2] = [:]
        var partnerMoves: [NodeRef: Vec2] = [:]
        for r in mine.sorted(by: { ($0.path, $0.node) < ($1.path, $1.node) }) {
            let ps = partners(of: r, in: e, mode: mode, tolerance: tolerance)
            var d = delta
            // On a centre line: drop the component that would break the symmetry.
            for (p, sign) in ps where p == r { d = Vec2(sign.x < 0 ? 0 : d.x, sign.y < 0 ? 0 : d.y) }
            moves[r] = d
            for (p, sign) in ps where p != r && !mine.contains(p) && partnerMoves[p] == nil {
                partnerMoves[p] = scale(d, sign)
            }
        }
        for (r, d) in moves.merging(partnerMoves, uniquingKeysWith: { a, _ in a }) {
            let p = e.paths[r.path]
            e.paths[r.path] = PathNodes.moveAnchor(p, r.node, to: PathNodes.anchor(p, r.node) + d)
        }
        return ShapeNodes.moveNodes(e, [], by: .zero)
    }

    /// Moves a Bézier handle and the mirror partners of that handle (the handles found at the
    /// reflected positions), each to the reflected target.
    public static func moveHandle(_ s: Shape, _ r: NodeRef, _ h: PathNodes.Handle, to point: Vec2, keepSmooth: Bool,
                                  mode: NodeMirrorMode, tolerance: Double? = nil) -> Shape {
        let e = ShapeNodes.editable(s)
        guard mode != .off, e.paths.indices.contains(r.path),
              let q = PathNodes.handle(e.paths[r.path], r.node, h) else {
            return ShapeNodes.moveHandle(s, r, h, to: point, keepSmooth: keepSmooth)
        }
        let box = e.bounds(), c = box.center, tol = matchTolerance(box, tolerance)
        var partners: [(NodeRef, PathNodes.Handle, Vec2)] = []
        for sign in mode.reflections {
            let target = reflect(q, about: c, sign)
            var best: (NodeRef, PathNodes.Handle, Double)?
            for (pi, p) in e.paths.enumerated() {
                for k in 0..<PathNodes.anchorCount(p) {
                    for hh in [PathNodes.Handle.incoming, .outgoing] {
                        let ref = NodeRef(shapeID: s.id, path: pi, node: k)
                        guard !(ref == r && hh == h), let v = PathNodes.handle(p, k, hh) else { continue }
                        let d = v.distance(to: target)
                        if d <= tol, d < (best?.2 ?? .infinity) { best = (ref, hh, d) }
                    }
                }
            }
            if let b = best, !partners.contains(where: { $0.0 == b.0 && $0.1 == b.1 }) { partners.append((b.0, b.1, sign)) }
        }
        var out = ShapeNodes.moveHandle(e, r, h, to: point, keepSmooth: keepSmooth)
        for (pr, ph, sign) in partners {
            let smooth = keepSmooth && PathNodes.isSmooth(e.paths[pr.path], pr.node)
            out = ShapeNodes.moveHandle(out, pr, ph, to: reflect(point, about: c, sign), keepSmooth: smooth)
        }
        return out
    }
}
