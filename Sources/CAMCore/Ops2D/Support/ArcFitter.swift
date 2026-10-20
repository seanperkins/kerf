import CADCore
import Foundation

/// Re-fits circular arcs to flattened polylines (e.g. Clipper round joins, offsets of
/// circles) so the post can emit G2/G3 instead of hundreds of short G1 moves.
public enum ArcFitter {
    public enum Segment: Hashable, Sendable {
        case line(to: Vec2)
        case arc(to: Vec2, center: Vec2, clockwise: Bool)

        public var end: Vec2 {
            switch self {
            case .line(let p), .arc(let p, _, _): return p
            }
        }
    }

    /// Minimum number of polyline segments replaced by one arc.
    public static let minimumSegments = 3
    /// Largest sweep of one fitted arc (keeps arcs unambiguous for every controller).
    public static let maximumSweep = Double.pi

    /// Fits `points` (an open walk; repeat the first point to close a loop). Every fitted arc
    /// passes through the polyline vertices it replaces within `tolerance`, and no chord
    /// strays further than `tolerance` from the arc.
    public static func fit(_ points: [Vec2], tolerance: Double) -> [Segment] {
        guard points.count > 1 else { return [] }
        var out: [Segment] = []
        var i = 0
        let n = points.count - 1
        while i < n {
            var best: (j: Int, center: Vec2, cw: Bool)?
            var j = i + minimumSegments
            while j <= n, let fit = check(points, i, j, tolerance) {
                best = (j, fit.center, fit.cw)
                j += 1
            }
            if let b = best {
                out.append(.arc(to: points[b.j], center: b.center, clockwise: b.cw))
                i = b.j
            } else {
                out.append(.line(to: points[i + 1]))
                i += 1
            }
        }
        return out
    }

    /// Circle through points i, mid, j, validated against every vertex and chord in between.
    static func check(_ p: [Vec2], _ i: Int, _ j: Int, _ tol: Double) -> (center: Vec2, cw: Bool)? {
        let a = p[i], b = p[(i + j) / 2], c = p[j]
        guard let center = circumcenter(a, b, c) else { return nil }
        let r = center.distance(to: a)
        guard r > tol * 2, r < 1e4 else { return nil }
        // Nearly straight runs are better left as lines.
        let halfSpan = a.distance(to: c) / 2
        if halfSpan < r, r - (r * r - halfSpan * halfSpan).squareRoot() < tol / 4 { return nil }
        var sweep = 0.0
        var sign = 0.0
        for k in i..<j {
            let u = p[k] - center, v = p[k + 1] - center
            if abs(v.length - r) > tol { return nil }
            let chord = p[k].distance(to: p[k + 1])
            guard chord < 2 * r else { return nil }
            let half = chord / 2
            if r - (r * r - half * half).squareRoot() > tol { return nil }
            let cr = u.cross(v)
            let ang = atan2(cr, u.dot(v))
            if abs(ang) > .pi / 2 { return nil }
            let s: Double = cr > 0 ? 1 : (cr < 0 ? -1 : 0)
            if s == 0 { return nil }
            if sign == 0 { sign = s } else if s != sign { return nil }
            sweep += abs(ang)
            if sweep > maximumSweep { return nil }
        }
        return (center, sign < 0)
    }

    static func circumcenter(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> Vec2? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let scale = max((b - a).lengthSquared, (c - a).lengthSquared)
        guard abs(d) > 1e-12 * max(scale, 1e-12) else { return nil }
        let a2 = a.lengthSquared, b2 = b.lengthSquared, c2 = c.lengthSquared
        let x = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
        let y = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
        return Vec2(x, y)
    }
}
