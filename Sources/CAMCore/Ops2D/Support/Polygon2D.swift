import CADCore
import Foundation

/// Small polygon/polyline utilities shared by the 2D generators. Polygons are point loops
/// without a repeated closing point (the `GeomKernel` convention).
public enum Polygon2D {
    /// Signed area (positive = counter-clockwise).
    public static func signedArea(_ p: [Vec2]) -> Double {
        guard p.count > 2 else { return 0 }
        var a = 0.0
        for i in 0..<p.count { a += p[i].cross(p[(i + 1) % p.count]) }
        return a / 2
    }

    /// Even-odd point-in-polygon test for one loop.
    public static func contains(_ poly: [Vec2], _ q: Vec2) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > q.y) != (b.y > q.y) {
                let x = (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x
                if q.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Even-odd containment against a set of loops (outer boundaries + holes).
    public static func regionContains(_ region: [[Vec2]], _ q: Vec2) -> Bool {
        region.reduce(false) { $0 != contains($1, q) }
    }

    /// Length of a polyline (closed adds the closing segment).
    public static func length(_ p: [Vec2], closed: Bool) -> Double {
        guard p.count > 1 else { return 0 }
        var l = zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        if closed { l += p.last!.distance(to: p[0]) }
        return l
    }

    /// Closest point on segment ab to q, with its parameter t in [0,1].
    public static func closestPoint(onSegment a: Vec2, _ b: Vec2, to q: Vec2) -> (point: Vec2, t: Double) {
        let ab = b - a
        let l2 = ab.lengthSquared
        guard l2 > 0 else { return (a, 0) }
        let t = min(1, max(0, (q - a).dot(ab) / l2))
        return (a + ab * t, t)
    }

    /// Distance from q to the nearest edge of a closed loop.
    public static func distance(from q: Vec2, toLoop p: [Vec2]) -> Double {
        guard !p.isEmpty else { return .infinity }
        var best = Double.infinity
        for i in 0..<p.count {
            let c = closestPoint(onSegment: p[i], p[(i + 1) % p.count], to: q).point
            best = min(best, c.distance(to: q))
        }
        return best
    }

    /// Rotates a closed loop so that it starts at the point on the loop nearest to `q`
    /// (inserting that point as a vertex when it falls inside an edge).
    public static func rotatedLoop(_ p: [Vec2], nearestTo q: Vec2, tolerance: Double) -> [Vec2] {
        guard p.count > 2 else { return p }
        var bestI = 0, bestT = 0.0, bestD = Double.infinity, bestP = p[0]
        for i in 0..<p.count {
            let (c, t) = closestPoint(onSegment: p[i], p[(i + 1) % p.count], to: q)
            let d = c.distance(to: q)
            if d < bestD - 1e-12 { bestD = d; bestI = i; bestT = t; bestP = c }
        }
        let a = p[bestI], b = p[(bestI + 1) % p.count]
        if bestP.distance(to: a) <= tolerance || bestT <= 0 { return Array(p[bestI...] + p[..<bestI]) }
        let next = (bestI + 1) % p.count
        if bestP.distance(to: b) <= tolerance || bestT >= 1 { return Array(p[next...] + p[..<next]) }
        return [bestP] + Array(p[next...] + p[..<next])
    }

    /// True when the straight segment ab lies inside `region` (even-odd loops), allowing
    /// `slack` of numerical error.
    public static func segmentInside(_ a: Vec2, _ b: Vec2, region: [[Vec2]], slack: Double) -> Bool {
        let len = a.distance(to: b)
        if len <= slack { return true }
        let clipped = GeomKernel.boolean(.intersection, subject: [[a, b]], clip: region,
                                         fillRule: .evenOdd, subjectsOpen: true)
        let inside = clipped.reduce(0) { $0 + length($1, closed: false) }
        return inside >= len - slack
    }

    /// Removes consecutive duplicate points (and a duplicated closing point for loops).
    public static func deduplicated(_ p: [Vec2], closed: Bool, tolerance: Double) -> [Vec2] {
        var out: [Vec2] = []
        out.reserveCapacity(p.count)
        for q in p where out.last.map({ $0.distance(to: q) > tolerance }) ?? true { out.append(q) }
        if closed, out.count > 1, out.last!.distance(to: out[0]) <= tolerance { out.removeLast() }
        return out
    }

    /// Normalises a set of closed loops into a clean region (outer loops CCW, holes CW)
    /// using the even-odd rule, so nested vectors become islands.
    public static func region(fromLoops loops: [[Vec2]]) -> [[Vec2]] {
        GeomKernel.boolean(.union, subject: loops.filter { $0.count > 2 }, clip: [], fillRule: .evenOdd)
    }

    /// `within[i][j]`: loop i lies within loop j, judged by area rather than by vertices (unlike
    /// `PathGeometry.nestingDepths`, which probes one vertex and is right for well-formed drawings):
    /// the part of i outside j has no more area than a `tolerance`-wide strip along i. So a part
    /// sitting in another part's notch or bridging it is not within it, a hole touching its outer
    /// edge is, and identical or near-identical outlines lie within each other. One Clipper
    /// difference per pair whose bounding boxes nest.
    public static func containment(_ loops: [[Vec2]], tolerance: Double) -> [[Bool]] {
        let boxes = loops.map { Rect2(points: $0) }
        return loops.indices.map { i in
            loops.indices.map { j in
                guard i != j, loops[i].count > 2, loops[j].count > 2 else { return false }
                let box = boxes[j].insetBy(-tolerance)
                guard box.contains(boxes[i].min), box.contains(boxes[i].max) else { return false }
                let outside = GeomKernel.boolean(.difference, subject: [loops[i]], clip: [loops[j]], fillRule: .nonZero)
                let area = outside.reduce(0) { $0 + abs(signedArea($1)) }
                return area <= tolerance * length(loops[i], closed: true)
            }
        }
    }
}
