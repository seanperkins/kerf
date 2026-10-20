import Foundation

/// A dimension drawn on the design for reference. Dimensions are annotations only: they are
/// never part of a shape, so toolpaths and vector export ignore them.
public struct DimensionAnnotation: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Distance between two points, along the line joining them.
        case aligned
        case horizontal
        case vertical
        /// points = [centre, point on the circle].
        case radius
        case diameter
        /// points = [vertex, end of first arm, end of second arm].
        case angle
    }

    public var id: UUID
    public var kind: Kind
    public var points: [Vec2]
    /// Linear: distance of the dimension line from the measured points (left of p0→p1 is
    /// positive). Angle: radius of the arc. Radial: unused.
    public var offset: Double

    public init(id: UUID = UUID(), kind: Kind, points: [Vec2], offset: Double = 0) {
        self.id = id; self.kind = kind; self.points = points; self.offset = offset
    }

    /// The measured value (length in document units, or degrees for angles).
    public var value: Double {
        switch kind {
        case .aligned: return points.count >= 2 ? points[0].distance(to: points[1]) : 0
        case .horizontal: return points.count >= 2 ? abs(points[1].x - points[0].x) : 0
        case .vertical: return points.count >= 2 ? abs(points[1].y - points[0].y) : 0
        case .radius: return points.count >= 2 ? points[0].distance(to: points[1]) : 0
        case .diameter: return points.count >= 2 ? 2 * points[0].distance(to: points[1]) : 0
        case .angle:
            guard points.count >= 3 else { return 0 }
            let a = points[1] - points[0], b = points[2] - points[0]
            var d = abs(atan2(a.cross(b), a.dot(b))) * 180 / .pi
            if d > 180 { d = 360 - d }
            return d
        }
    }

    /// Dimension line end points for linear kinds (nil otherwise).
    public var dimensionLine: (Vec2, Vec2)? {
        guard points.count >= 2 else { return nil }
        let a = points[0], b = points[1]
        switch kind {
        case .aligned:
            let n = (b - a).normalized.perpendicular
            return (a + n * offset, b + n * offset)
        case .horizontal:
            let y = max(a.y, b.y) + offset
            return (Vec2(a.x, y), Vec2(b.x, y))
        case .vertical:
            let x = max(a.x, b.x) + offset
            return (Vec2(x, a.y), Vec2(x, b.y))
        default: return nil
        }
    }

    /// Offset that puts the dimension line through `p` (linear kinds) or the arc at `p` (angle).
    public func offset(through p: Vec2) -> Double {
        guard points.count >= 2 else { return 0 }
        let a = points[0], b = points[1]
        switch kind {
        case .aligned: return (p - a).dot((b - a).normalized.perpendicular)
        case .horizontal: return p.y - max(a.y, b.y)
        case .vertical: return p.x - max(a.x, b.x)
        case .angle: return p.distance(to: a)
        default: return 0
        }
    }
}
