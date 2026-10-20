import Foundation

/// Snapping to object points (anchors, segment midpoints, shape centres) with grid fallback.
public struct SnapEngine: Sendable {
    public enum Kind: String, Sendable { case none, grid, node, midpoint, center }

    public struct Result: Equatable, Sendable {
        public var point: Vec2
        public var kind: Kind
        public init(point: Vec2, kind: Kind) { self.point = point; self.kind = kind }
    }

    public struct Target: Equatable, Sendable {
        public var point: Vec2
        public var kind: Kind
        public init(point: Vec2, kind: Kind) { self.point = point; self.kind = kind }
    }

    public var targets: [Target]

    public init(targets: [Target]) { self.targets = targets }

    /// Collects snap targets from `shapes` (callers exclude the shapes being dragged).
    public init(shapes: [Shape], includeMidpoints: Bool = true, includeCenters: Bool = true) {
        var t: [Target] = []
        for s in shapes {
            for p in s.paths {
                t.append(Target(point: p.start, kind: .node))
                var cur = p.start
                for seg in p.segments {
                    t.append(Target(point: seg.end, kind: .node))
                    if includeMidpoints {
                        let one = Path(start: cur, segments: [seg])
                        t.append(Target(point: PathNodes.point(one, segment: 0, t: 0.5), kind: .midpoint))
                    }
                    cur = seg.end
                }
                if includeMidpoints, p.isClosed, !cur.isApproximatelyEqual(to: p.start, tolerance: 1e-9) {
                    t.append(Target(point: cur.lerp(to: p.start, 0.5), kind: .midpoint))
                }
            }
            if includeCenters {
                let b = s.bounds()
                if !b.isEmpty { t.append(Target(point: b.center, kind: .center)) }
            }
        }
        targets = t
    }

    /// Snaps `p`: the nearest object target within `tolerance` wins (nodes beat midpoints and
    /// centres at equal distance); otherwise the grid (when `grid > 0`); otherwise unchanged.
    public func snap(_ p: Vec2, tolerance: Double, grid: Double) -> Result {
        var best: Target?
        var bestD = Double.infinity
        for t in targets {
            let d = t.point.distance(to: p)
            guard d <= tolerance else { continue }
            if d < bestD - 1e-12 || (abs(d - bestD) <= 1e-12 && t.kind == .node && best?.kind != .node) {
                best = t; bestD = d
            }
        }
        if let b = best { return Result(point: b.point, kind: b.kind) }
        if grid > 0 {
            return Result(point: Vec2((p.x / grid).rounded() * grid, (p.y / grid).rounded() * grid), kind: .grid)
        }
        return Result(point: p, kind: .none)
    }

    /// Translation that snaps any of `anchors` (moved by `delta`) onto an object target; falls
    /// back to a grid-snapped delta. Used when dragging a selection.
    public func snapDelta(_ delta: Vec2, anchors: [Vec2], tolerance: Double, grid: Double) -> Vec2 {
        var best: (Vec2, Double)?
        for a in anchors {
            let moved = a + delta
            for t in targets {
                let d = t.point.distance(to: moved)
                if d <= tolerance, d < (best?.1 ?? .infinity) { best = (t.point - a, d) }
            }
        }
        if let b = best { return b.0 }
        guard grid > 0 else { return delta }
        return Vec2((delta.x / grid).rounded() * grid, (delta.y / grid).rounded() * grid)
    }
}
