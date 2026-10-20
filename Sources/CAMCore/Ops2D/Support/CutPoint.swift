import CADCore
import Foundation

/// A point on a cutting path: material-frame XY plus depth below the material top
/// (positive = into the stock). Generators build `[CutPoint]` and hand them to
/// `ToolpathBuilder`, which maps them through `MachineCoordinates`.
public struct CutPoint: Hashable, Sendable {
    public var xy: Vec2
    public var depth: Double

    public init(_ xy: Vec2, depth: Double) { self.xy = xy; self.depth = depth }
}

/// A 2D chain to cut: an open polyline or a closed loop (no repeated closing point).
public struct Chain2D: Hashable, Sendable {
    public var points: [Vec2]
    public var isClosed: Bool

    public init(points: [Vec2], isClosed: Bool) { self.points = points; self.isClosed = isClosed }

    public var length: Double { Polygon2D.length(points, closed: isClosed) }
    public var start: Vec2 { points.first ?? .zero }
    public var end: Vec2 { isClosed ? start : (points.last ?? .zero) }

    public func reversed() -> Chain2D {
        guard isClosed, points.count > 1 else { return Chain2D(points: points.reversed(), isClosed: isClosed) }
        return Chain2D(points: [points[0]] + points.dropFirst().reversed(), isClosed: true)
    }

    /// The vertex list walked from start to end (closed loops repeat the start at the end).
    public var walk: [Vec2] { isClosed && !points.isEmpty ? points + [points[0]] : points }
}

/// Extracts flattened closed loops and open polylines from shapes.
public enum ShapeGeometry {
    public static func loops(of shapes: [Shape], tolerance: Double) -> (closed: [[Vec2]], open: [[Vec2]]) {
        var closed: [[Vec2]] = [], open: [[Vec2]] = []
        for shape in shapes {
            for path in shape.paths {
                let pts = Polygon2D.deduplicated(path.flattened(tolerance: tolerance), closed: path.isClosed,
                                                 tolerance: tolerance * 1e-3)
                if path.isClosed {
                    if pts.count > 2 { closed.append(pts) }
                } else if pts.count > 1 {
                    open.append(pts)
                }
            }
        }
        return (closed, open)
    }
}
