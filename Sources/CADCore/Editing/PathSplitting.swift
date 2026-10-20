import Foundation

/// Positions along a path as `segment index + t` (t in 0...1 within the segment), path
/// intersections in those terms, and sub-path extraction. Lines and arcs split exactly; cubics
/// split with de Casteljau at the parameter found on their flattening.
public enum PathSplitting {
    /// A flattened path with the path parameter of every point.
    public struct Sampled: Sendable {
        public var points: [Vec2]
        public var params: [Double]
    }

    /// Flattening that remembers parameters. Closed paths end with an explicit return to the start.
    public static func sample(_ path: Path, tolerance: Double) -> Sampled {
        var pts = [path.start], params = [0.0]
        var cur = path.start
        let segs = closedSegments(path)
        for (j, seg) in segs.enumerated() {
            var tmp: [Vec2] = []
            Flattening.append(segment: seg, from: cur, tolerance: tolerance, to: &tmp)
            let n = tmp.count
            for (k, p) in tmp.enumerated() {
                pts.append(p)
                params.append(Double(j) + Double(k + 1) / Double(n))
            }
            cur = seg.end
        }
        return Sampled(points: pts, params: params)
    }

    /// Segments including an explicit closing line for closed paths that need one.
    public static func closedSegments(_ path: Path) -> [PathSegment] {
        var segs = path.segments
        if path.isClosed, !segs.isEmpty, !path.end.isApproximatelyEqual(to: path.start, tolerance: 1e-12) {
            segs.append(.line(to: path.start))
        }
        return segs
    }

    /// Parameters along `a` where it crosses or touches `b`.
    public static func intersections(_ a: Sampled, _ b: Sampled, tolerance: Double) -> [Double] {
        var out: [Double] = []
        let nb = b.points.count - 1
        guard a.points.count > 1, nb > 0 else { return [] }
        let bBox = Rect2(points: b.points).insetBy(-tolerance)
        for i in 0..<(a.points.count - 1) {
            let p1 = a.points[i], p2 = a.points[i + 1]
            guard bBox.intersects(Rect2(points: [p1, p2])) else { continue }
            for k in 0..<nb {
                let q1 = b.points[k], q2 = b.points[k + 1]
                if max(p1.x, p2.x) < min(q1.x, q2.x) - tolerance || min(p1.x, p2.x) > max(q1.x, q2.x) + tolerance { continue }
                if max(p1.y, p2.y) < min(q1.y, q2.y) - tolerance || min(p1.y, p2.y) > max(q1.y, q2.y) + tolerance { continue }
                if let u = segmentHit(p1, p2, q1, q2) {
                    out.append(a.params[i] + u * (a.params[i + 1] - a.params[i]))
                }
            }
        }
        return dedupe(out.sorted(), tolerance: 1e-6)
    }

    /// Parameters along `a` where it crosses itself (non-adjacent pieces).
    public static func selfIntersections(_ a: Sampled) -> [Double] {
        let n = a.points.count - 1
        guard n >= 3 else { return [] }
        var out: [Double] = []
        for i in 0..<n {
            for k in (i + 2)..<max(i + 2, n) where !(i == 0 && k == n - 1 && a.points[0] == a.points[n]) {
                if let u = segmentHit(a.points[i], a.points[i + 1], a.points[k], a.points[k + 1], strict: true) {
                    out.append(a.params[i] + u * (a.params[i + 1] - a.params[i]))
                    if let v = segmentHit(a.points[k], a.points[k + 1], a.points[i], a.points[i + 1], strict: true) {
                        out.append(a.params[k] + v * (a.params[k + 1] - a.params[k]))
                    }
                }
            }
        }
        return dedupe(out.sorted(), tolerance: 1e-6)
    }

    /// Parameter of the point of `path` nearest to `p`, and its distance.
    public static func nearestParameter(_ s: Sampled, to p: Vec2) -> (param: Double, distance: Double) {
        var best = (param: 0.0, distance: Double.infinity)
        for i in 0..<max(0, s.points.count - 1) {
            let a = s.points[i], b = s.points[i + 1]
            let ab = b - a
            let l2 = ab.lengthSquared
            let u = l2 > 0 ? max(0, min(1, (p - a).dot(ab) / l2)) : 0
            let d = p.distance(to: a + ab * u)
            if d < best.distance { best = (s.params[i] + u * (s.params[i + 1] - s.params[i]), d) }
        }
        return best
    }

    /// Point at a path parameter.
    public static func point(_ path: Path, at s: Double) -> Vec2 {
        let segs = closedSegments(path)
        guard !segs.isEmpty else { return path.start }
        let j = min(max(Int(s.rounded(.down)), 0), segs.count - 1)
        let t = min(max(s - Double(j), 0), 1)
        let from = j == 0 ? path.start : segs[j - 1].end
        return split(segs[j], from: from, at: t).point
    }

    /// Open sub-path from parameter `s0` to `s1`. For closed paths `s1 < s0` wraps through the
    /// start point.
    public static func subpath(_ path: Path, from s0: Double, to s1: Double) -> Path {
        let segs = closedSegments(path)
        let n = Double(segs.count)
        guard !segs.isEmpty else { return path }
        var end = s1
        if path.isClosed, end <= s0 { end += n }
        var out = Path(start: point(path, at: s0), isClosed: false)
        var s = s0
        while s < end - 1e-12 {
            let jj = Int((s + 1e-12).rounded(.down))
            let j = ((jj % segs.count) + segs.count) % segs.count
            let base = Double(jj)
            let t0 = s - base, t1 = min(end - base, 1)
            let from = j == 0 ? path.start : segs[j - 1].end
            out.segments.append(piece(segs[j], from: from, t0: max(0, t0), t1: t1))
            s = base + t1
            if t1 >= 1 { s = base + 1 }
        }
        return out
    }

    // MARK: - Segment splitting

    /// Splits `seg` (starting at `from`) at `t`: the part before, the part after and the point.
    public static func split(_ seg: PathSegment, from a: Vec2, at t: Double) -> (first: PathSegment, second: PathSegment, point: Vec2) {
        switch seg {
        case .line(let to):
            let m = a.lerp(to: to, t)
            return (.line(to: m), .line(to: to), m)
        case .arc(let to, let c, let cw):
            let sweep = Flattening.arcSweep(from: a, to: to, center: c, clockwise: cw)
            let r = a.distance(to: c)
            let ang = (a - c).angle + sweep * t
            let m = c + Vec2(cos(ang), sin(ang)) * r
            return (.arc(to: m, center: c, clockwise: cw), .arc(to: to, center: c, clockwise: cw), m)
        case .cubic(let to, let c1, let c2):
            let p01 = a.lerp(to: c1, t), p12 = c1.lerp(to: c2, t), p23 = c2.lerp(to: to, t)
            let p012 = p01.lerp(to: p12, t), p123 = p12.lerp(to: p23, t)
            let m = p012.lerp(to: p123, t)
            return (.cubic(to: m, control1: p01, control2: p012), .cubic(to: to, control1: p123, control2: p23), m)
        }
    }

    /// The part of `seg` between parameters t0 < t1.
    static func piece(_ seg: PathSegment, from a: Vec2, t0: Double, t1: Double) -> PathSegment {
        var s = seg, start = a
        if t0 > 1e-12 {
            let sp = split(seg, from: a, at: t0)
            s = sp.second; start = sp.point
        }
        guard t1 < 1 - 1e-12 else { return s }
        let local = (t1 - t0) / (1 - t0)
        return split(s, from: start, at: local).first
    }

    // MARK: - Helpers

    /// Parameter along p1→p2 where it meets q1→q2 (nil when apart or parallel).
    static func segmentHit(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2, strict: Bool = false) -> Double? {
        let r = p2 - p1, s = q2 - q1
        let den = r.cross(s)
        guard abs(den) > 1e-14 else { return nil }
        let t = (q1 - p1).cross(s) / den, u = (q1 - p1).cross(r) / den
        let e = strict ? 1e-9 : -1e-9
        guard t >= -1e-9, t <= 1 + 1e-9, u > e, u < 1 - e else { return nil }
        if strict, t <= 1e-9 || t >= 1 - 1e-9 { return nil }
        return min(max(t, 0), 1)
    }

    static func dedupe(_ sorted: [Double], tolerance: Double) -> [Double] {
        var out: [Double] = []
        for v in sorted where out.last.map({ abs($0 - v) > tolerance }) ?? true { out.append(v) }
        return out
    }
}
