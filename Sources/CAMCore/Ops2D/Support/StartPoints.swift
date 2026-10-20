import CADCore
import Foundation

/// Chooses where a closed toolpath loop starts.
public enum StartPoints {
    /// Rotates closed `chain` to start at the requested point. `.nearest` leaves it as ordered;
    /// `.vectorStart` uses the source vector start (from `sourceStarts`) nearest to the loop; the
    /// box sides use the middle of that side of the loop's bounding box. Open chains are unchanged.
    public static func rotate(_ chain: Chain2D, to start: ProfileStartPoint, sourceStarts: [Vec2],
                              tolerance: Double) -> Chain2D {
        guard chain.isClosed, chain.points.count > 2 else { return chain }
        let target: Vec2
        switch start {
        case .nearest:
            return chain
        case .vectorStart:
            guard let s = sourceStarts.min(by: {
                Polygon2D.distance(from: $0, toLoop: chain.points) < Polygon2D.distance(from: $1, toLoop: chain.points)
            }) else { return chain }
            target = s
        case .left, .right, .bottom, .top:
            let b = Rect2(points: chain.points)
            let far = max(b.width, b.height) * 100 + 1
            let c = Vec2((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2)
            switch start {
            case .left: target = Vec2(b.min.x - far, c.y)
            case .right: target = Vec2(b.max.x + far, c.y)
            case .bottom: target = Vec2(c.x, b.min.y - far)
            default: target = Vec2(c.x, b.max.y + far)
            }
        }
        var out = chain
        out.points = Polygon2D.rotatedLoop(chain.points, nearestTo: target, tolerance: tolerance)
        return out
    }
}
