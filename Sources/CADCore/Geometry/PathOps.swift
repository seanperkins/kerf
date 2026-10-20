import Foundation

/// Shape-level geometry operations (boolean, offset, join). Booleans/offsets return
/// polyline paths (arcs are flattened with `tolerance`).
public enum PathOps {
    public static func union(_ paths: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        let polys = closedPolygons(paths, tolerance)
        return wrap(GeomKernel.boolean(.union, subject: polys, clip: []))
    }

    public static func subtract(_ a: [Path], minus b: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.difference, subject: closedPolygons(a, tolerance), clip: closedPolygons(b, tolerance)))
    }

    public static func intersect(_ a: [Path], with b: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.intersection, subject: closedPolygons(a, tolerance), clip: closedPolygons(b, tolerance)))
    }

    /// Offset closed paths outward (positive) or inward (negative).
    public static func offset(_ paths: [Path], by distance: Double, join: GeomKernel.Join = .round,
                              tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.offset(closedPolygons(paths, tolerance), by: distance, join: join,
                               arcTolerance: tolerance))
    }

    /// Join open paths whose endpoints are within `tolerance`, closing loops when possible.
    public static func joinOpenPaths(_ paths: [Path], tolerance: Double) -> [Path] {
        // TODO(cad-io): implement endpoint matching + reversal.
        paths
    }

    static func closedPolygons(_ paths: [Path], _ tol: Double) -> [[Vec2]] {
        paths.filter(\.isClosed).map { $0.flattened(tolerance: tol) }
    }

    static func wrap(_ polys: [[Vec2]]) -> [Path] {
        polys.filter { $0.count > 2 }.map { Path(points: $0, closed: true) }
    }
}
