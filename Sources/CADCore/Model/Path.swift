import Foundation

/// One segment of a `Path`; the segment starts where the previous one ended.
public enum PathSegment: Codable, Hashable, Sendable {
    case line(to: Vec2)
    /// Circular arc around `center`. Radius = |start - center| (end is assumed on the circle).
    case arc(to: Vec2, center: Vec2, clockwise: Bool)
    case cubic(to: Vec2, control1: Vec2, control2: Vec2)

    public var end: Vec2 {
        switch self {
        case .line(let to), .arc(let to, _, _), .cubic(let to, _, _): return to
        }
    }
}

/// A connected sequence of segments: a "vector" in VCarve terms.
/// Closed paths implicitly return to `start` (an explicit closing line is added only if the
/// last segment does not already end at `start`).
public struct Path: Codable, Hashable, Sendable {
    public var start: Vec2
    public var segments: [PathSegment]
    public var isClosed: Bool

    public init(start: Vec2, segments: [PathSegment] = [], isClosed: Bool = false) {
        self.start = start; self.segments = segments; self.isClosed = isClosed
    }

    /// Polyline convenience.
    public init(points: [Vec2], closed: Bool) {
        start = points.first ?? .zero
        segments = points.dropFirst().map { .line(to: $0) }
        isClosed = closed
    }

    public var end: Vec2 { segments.last?.end ?? start }
    public var isEmpty: Bool { segments.isEmpty }

    /// Start point of segment `i`.
    public func startOfSegment(_ i: Int) -> Vec2 { i == 0 ? start : segments[i - 1].end }

    /// Default chordal tolerance used when callers do not supply one (document units).
    public static let defaultTolerance = 0.001

    /// Flatten to a polyline with max chordal deviation `tolerance`.
    /// For closed paths the returned array does NOT repeat the first point.
    public func flattened(tolerance: Double = Path.defaultTolerance) -> [Vec2] {
        var pts = [start]
        var cur = start
        for seg in segments {
            Flattening.append(segment: seg, from: cur, tolerance: tolerance, to: &pts)
            cur = seg.end
        }
        if isClosed, pts.count > 1, pts.last!.isApproximatelyEqual(to: pts[0], tolerance: 1e-12) {
            pts.removeLast()
        }
        return pts
    }

    /// Signed area of the flattened closed path (positive = counter-clockwise).
    public func signedArea(tolerance: Double = Path.defaultTolerance) -> Double {
        let p = flattened(tolerance: tolerance)
        guard p.count > 2 else { return 0 }
        var a = 0.0
        for i in 0..<p.count { a += p[i].cross(p[(i + 1) % p.count]) }
        return a / 2
    }

    public var isClockwise: Bool { signedArea() < 0 }

    /// Bounds of the flattened geometry (exact for lines, tight within tolerance for curves).
    public func bounds(tolerance: Double = Path.defaultTolerance) -> Rect2 {
        Rect2(points: flattened(tolerance: tolerance))
    }

    public func length(tolerance: Double = Path.defaultTolerance) -> Double {
        var p = flattened(tolerance: tolerance)
        if isClosed, let f = p.first { p.append(f) }
        return zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Transform the path. Arcs stay arcs under conformal transforms, otherwise they are
    /// converted to cubic Béziers first.
    public func transformed(_ t: Transform2D) -> Path {
        var out = Path(start: t.apply(start), isClosed: isClosed)
        var cur = start
        for seg in segments {
            switch seg {
            case .line(let to):
                out.segments.append(.line(to: t.apply(to)))
            case .arc(let to, let center, let cw):
                if t.isConformal {
                    out.segments.append(.arc(to: t.apply(to), center: t.apply(center),
                                             clockwise: t.isMirroring ? !cw : cw))
                } else {
                    for c in Flattening.arcToCubics(from: cur, to: to, center: center, clockwise: cw) {
                        if case .cubic(let e, let c1, let c2) = c {
                            out.segments.append(.cubic(to: t.apply(e), control1: t.apply(c1), control2: t.apply(c2)))
                        }
                    }
                }
            case .cubic(let to, let c1, let c2):
                out.segments.append(.cubic(to: t.apply(to), control1: t.apply(c1), control2: t.apply(c2)))
            }
            cur = seg.end
        }
        return out
    }

    /// Same geometry traversed in the opposite direction.
    public func reversed() -> Path {
        guard !segments.isEmpty else { return self }
        var out = Path(start: end, isClosed: isClosed)
        for i in stride(from: segments.count - 1, through: 0, by: -1) {
            let from = startOfSegment(i)
            switch segments[i] {
            case .line: out.segments.append(.line(to: from))
            case .arc(_, let c, let cw): out.segments.append(.arc(to: from, center: c, clockwise: !cw))
            case .cubic(_, let c1, let c2): out.segments.append(.cubic(to: from, control1: c2, control2: c1))
            }
        }
        return out
    }
}
