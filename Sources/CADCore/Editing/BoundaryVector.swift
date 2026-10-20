import Foundation

/// Closed vectors wrapped around a selection.
public enum BoundaryVector {
    public enum Kind: String, Codable, CaseIterable, Sendable { case rectangle, convexHull, shrinkWrap }

    /// Boundary around `paths` grown by `margin`. Shrink-wrap follows the outline, bridging
    /// gaps narrower than `2 × gap` (a morphological closing).
    public static func make(_ kind: Kind, around paths: [Path], margin: Double, gap: Double, tolerance: Double) -> [Path] {
        let pts = paths.flatMap { $0.flattened(tolerance: tolerance) }
        guard !pts.isEmpty else { return [] }
        switch kind {
        case .rectangle:
            let b = Rect2(points: pts).insetBy(-max(margin, 0))
            guard b.width > 0, b.height > 0 else { return [] }
            return [ShapeFactory.rectangle(b)]
        case .convexHull:
            let hull = convexHull(pts)
            guard hull.count >= 3 else { return [] }
            let p = Path(points: hull, closed: true)
            return margin > 0 ? PathOps.offset([p], by: margin, join: .round, tolerance: tolerance) : [p]
        case .shrinkWrap:
            // Regions: closed paths filled, open paths as thin outlines.
            var regions = PathOps.union(shapes: [paths.filter(\.isClosed)], tolerance: tolerance)
            let open = paths.filter { !$0.isClosed }
            if !open.isEmpty { regions = PathOps.union(regions, PathOps.offsetOpen(open, by: tolerance * 2, tolerance: tolerance), tolerance: tolerance) }
            guard !regions.isEmpty else { return [] }
            let g = max(gap, tolerance)
            let closedUp = PathOps.offset(PathOps.offset(regions, by: g + max(margin, 0), tolerance: tolerance), by: -g, tolerance: tolerance)
            // Outer loops only: holes inside the wrap are dropped.
            let depths = PathGeometry.nestingDepths(closedUp, tolerance: tolerance)
            return zip(closedUp, depths).filter { $0.1 == 0 }.map(\.0)
        }
    }

    /// Andrew's monotone chain; counter-clockwise, no repeated first point.
    public static func convexHull(_ points: [Vec2]) -> [Vec2] {
        let p = Array(Set(points.map { [$0.x, $0.y] })).map { Vec2($0[0], $0[1]) }.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard p.count >= 3 else { return p }
        func cross(_ o: Vec2, _ a: Vec2, _ b: Vec2) -> Double { (a - o).cross(b - o) }
        var lower: [Vec2] = [], upper: [Vec2] = []
        for q in p {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        for q in p.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}
