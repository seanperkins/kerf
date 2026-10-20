import Foundation

/// Extending open vectors along their end directions until they meet other vectors.
public enum Extend {
    /// `path` with its free ends extended (straight, along the end tangent) to the nearest
    /// boundary crossing within `maxDistance`. Ends that hit nothing are left alone.
    public static func toBoundaries(_ path: Path, boundaries: [Path], maxDistance: Double, tolerance: Double) -> Path {
        guard !path.isClosed, !path.segments.isEmpty else { return path }
        let flat = max(tolerance / 4, 1e-6)
        let polys = boundaries.map { PathSplitting.sample($0, tolerance: flat).points }
        var out = path
        // End.
        let endDir = tangent(out, atEnd: true)
        if let d = hit(from: out.end, dir: endDir, polys: polys, maxDistance: maxDistance, tolerance: tolerance) {
            let target = out.end + endDir * d
            if case .line = out.segments.last! { out.segments[out.segments.count - 1] = .line(to: target) }
            else { out.segments.append(.line(to: target)) }
        }
        // Start.
        let startDir = tangent(out, atEnd: false)
        if let d = hit(from: out.start, dir: startDir, polys: polys, maxDistance: maxDistance, tolerance: tolerance) {
            let target = out.start + startDir * d
            if case .line = out.segments.first! { out.start = target }
            else { out.segments.insert(.line(to: out.start), at: 0); out.start = target }
        }
        return out
    }

    /// Outward unit tangent at an end.
    static func tangent(_ p: Path, atEnd: Bool) -> Vec2 {
        guard let seg = atEnd ? p.segments.last : p.segments.first else { return .zero }
        let from = atEnd ? p.startOfSegment(p.segments.count - 1) : p.start
        // Direction of travel at the chosen end of the segment.
        let travel: Vec2
        switch seg {
        case .line(let to): travel = to - from
        case .arc(let to, let c, let cw):
            let r = (atEnd ? to : from) - c
            travel = cw ? Vec2(r.y, -r.x) : r.perpendicular
        case .cubic(let to, let c1, let c2):
            if atEnd { travel = !to.isApproximatelyEqual(to: c2, tolerance: 1e-12) ? to - c2 : to - c1 }
            else { travel = !c1.isApproximatelyEqual(to: from, tolerance: 1e-12) ? c1 - from : c2 - from }
        }
        return atEnd ? travel.normalized : (-travel).normalized
    }

    /// Distance along the ray to the nearest polyline crossing (beyond `tolerance`).
    static func hit(from o: Vec2, dir: Vec2, polys: [[Vec2]], maxDistance: Double, tolerance: Double) -> Double? {
        guard dir != .zero else { return nil }
        var best: Double?
        for poly in polys {
            for (a, b) in zip(poly, poly.dropFirst()) {
                let s = b - a
                let den = dir.cross(s)
                guard abs(den) > 1e-14 else { continue }
                let t = (a - o).cross(s) / den, u = (a - o).cross(dir) / den
                guard t > tolerance, t <= maxDistance, u >= -1e-9, u <= 1 + 1e-9 else { continue }
                if t < (best ?? .infinity) { best = t }
            }
        }
        return best
    }
}
