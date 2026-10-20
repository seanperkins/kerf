import Foundation

/// Replaces dense polylines (traced or imported data) with the fewest lines and circular arcs
/// that stay within a tolerance of the original points.
public enum CurveFit {
    /// Fitted copy of `path`. Curved input is flattened first (at `tolerance / 4`).
    public static func fit(_ path: Path, tolerance: Double) -> Path {
        var pts = path.flattened(tolerance: max(tolerance / 4, 1e-6))
        if path.isClosed, let f = pts.first { pts.append(f) }
        pts = dedupe(pts)
        guard pts.count >= 3, tolerance > 0 else { return path }
        var out = Path(start: pts[0], isClosed: path.isClosed)
        var i = 0
        while i < pts.count - 1 {
            let (j, seg) = longestFit(pts, from: i, tolerance: tolerance)
            out.segments.append(seg)
            i = j
        }
        if path.isClosed, let last = out.segments.indices.last, case .line(let to) = out.segments[last],
           to.isApproximatelyEqual(to: out.start, tolerance: 1e-12), out.segments.count > 2 {
            out.segments.removeLast()  // implicit closing line
        }
        return out
    }

    /// Segment count before and after (for UI feedback).
    public static func segmentCount(_ paths: [Path]) -> Int { paths.reduce(0) { $0 + $1.segments.count } }

    // MARK: - Internals

    static func dedupe(_ pts: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where out.last.map({ !$0.isApproximatelyEqual(to: p, tolerance: 1e-12) }) ?? true { out.append(p) }
        return out
    }

    /// Furthest index reachable from `i` by one line or arc, and that segment.
    static func longestFit(_ pts: [Vec2], from i: Int, tolerance tol: Double) -> (Int, PathSegment) {
        let maxSpan = 4000
        var lineEnd = i + 1
        var arcEnd = i
        var arcSeg: PathSegment?
        var lineAlive = true, arcAlive = true
        var j = i + 2
        while j < pts.count, j - i <= maxSpan, lineAlive || arcAlive {
            if lineAlive {
                if fitsLine(pts, i, j, tol) { lineEnd = j } else { lineAlive = false }
            }
            if arcAlive {
                if let s = fitArc(pts, i, j, tol) { arcEnd = j; arcSeg = s } else if j - i > 3 { arcAlive = false }
            }
            j += 1
        }
        if let s = arcSeg, arcEnd > lineEnd { return (arcEnd, s) }
        return (lineEnd, .line(to: pts[lineEnd]))
    }

    static func fitsLine(_ pts: [Vec2], _ i: Int, _ j: Int, _ tol: Double) -> Bool {
        let a = pts[i], b = pts[j]
        for k in (i + 1)..<j where VectorValidator.segmentDistance(pts[k], a, b) > tol { return false }
        return true
    }

    /// Arc through pts[i], a middle point and pts[j] that every point in between stays within
    /// `tol` of, with the points running monotonically round the centre.
    static func fitArc(_ pts: [Vec2], _ i: Int, _ j: Int, _ tol: Double) -> PathSegment? {
        let a = pts[i], b = pts[j], m = pts[(i + j) / 2]
        guard let c = ArcConstruction.circumcenter(a, m, b) else { return nil }
        let r = a.distance(to: c)
        guard r > tol, r < 1e5 * tol else { return nil }  // huge radius: a line fits as well
        let ccw = (m - a).cross(b - m) > 0
        var prevAngle = 0.0
        let a0 = (a - c).angle
        for k in i...j {
            let p = pts[k]
            if abs(p.distance(to: c) - r) > tol { return nil }
            // Unwrapped sweep from the start must grow monotonically.
            var s = (p - c).angle - a0
            if ccw { while s < -1e-9 { s += 2 * .pi } } else { while s > 1e-9 { s -= 2 * .pi } }
            let sweep = abs(s)
            if k > i, sweep + 1e-9 < prevAngle { return nil }
            prevAngle = sweep
            // Midpoints of the chords must also lie near the arc.
            if k > i {
                let mid = (pts[k - 1] + p) / 2
                if r - mid.distance(to: c) > tol { return nil }
            }
        }
        // At most a half circle per arc (unambiguous for every post and for later editing).
        guard prevAngle <= .pi + 1e-6 else { return nil }
        return .arc(to: b, center: c, clockwise: !ccw)
    }
}
