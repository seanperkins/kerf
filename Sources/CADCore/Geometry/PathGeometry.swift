import Foundation

/// Flattening, closedness and orientation helpers over paths and shapes.
public enum PathGeometry {
    /// Flatten every path of every shape. Closed polylines do not repeat their first point.
    public static func flatten(_ shapes: [Shape], tolerance: Double = Path.defaultTolerance) -> [[Vec2]] {
        shapes.flatMap { $0.paths.map { $0.flattened(tolerance: tolerance) } }
    }

    /// Path with the requested winding (closed paths only; open paths are returned unchanged).
    public static func oriented(_ path: Path, counterClockwise: Bool, tolerance: Double = Path.defaultTolerance) -> Path {
        guard path.isClosed else { return path }
        let ccw = path.signedArea(tolerance: tolerance) > 0
        return ccw == counterClockwise ? path : path.reversed()
    }

    /// Nesting depth of each closed path (0 = outermost). Open paths get depth 0.
    public static func nestingDepths(_ paths: [Path], tolerance: Double = Path.defaultTolerance) -> [Int] {
        let polys = paths.map { $0.isClosed ? $0.flattened(tolerance: tolerance) : [] }
        let boxes = polys.map { Rect2(points: $0) }
        return polys.indices.map { i in
            guard let probe = polys[i].first, polys[i].count > 2 else { return 0 }
            var depth = 0
            for j in polys.indices where j != i && polys[j].count > 2 && boxes[j].contains(probe) {
                // Ignore identical outlines (would count each other).
                if boxes[j] == boxes[i], abs(area(polys[j])) == abs(area(polys[i])) { continue }
                if contains(polys[j], probe) { depth += 1 }
            }
            return depth
        }
    }

    /// Outer loops counter-clockwise, holes clockwise (alternating by nesting depth).
    public static func normalizedOrientation(_ paths: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        let depths = nestingDepths(paths, tolerance: tolerance)
        return zip(paths, depths).map { oriented($0, counterClockwise: $1.isMultiple(of: 2), tolerance: tolerance) }
    }

    /// Even-odd point-in-polygon test (polygon need not repeat its first point).
    public static func contains(_ poly: [Vec2], _ p: Vec2) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Signed shoelace area of a polygon (positive = counter-clockwise).
    public static func area(_ poly: [Vec2]) -> Double {
        guard poly.count > 2 else { return 0 }
        var a = 0.0
        for i in poly.indices { a += poly[i].cross(poly[(i + 1) % poly.count]) }
        return a / 2
    }

    /// Close every open path whose ends meet within `tolerance`.
    public static func closeNearlyClosed(_ paths: [Path], tolerance: Double) -> [Path] {
        paths.map { PathOps.closeIfNearlyClosed($0, tolerance: tolerance) }
    }

    /// Union of the bounds of `shapes`.
    public static func bounds(of shapes: [Shape], tolerance: Double = Path.defaultTolerance) -> Rect2 {
        shapes.reduce(Rect2.empty) { $0.union($1.bounds(tolerance: tolerance)) }
    }
}
