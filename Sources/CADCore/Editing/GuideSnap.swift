import Foundation

/// A construction guide: an infinite horizontal or vertical line (never cut).
public struct GuideLine: Codable, Hashable, Sendable {
    /// Vertical guides sit at x = `position`, horizontal ones at y = `position`.
    public var isVertical: Bool
    public var position: Double

    public init(isVertical: Bool, position: Double) { self.isVertical = isVertical; self.position = position }
}

/// Snapping one coordinate at a time to guides and to horizontal/vertical "extension" lines
/// through existing nodes (so new points line up with existing geometry).
public enum AxisSnap {
    public struct Result: Equatable, Sendable {
        public var point: Vec2
        /// The x / y line the point snapped to, if any, and the node it lines up with (nil for guides).
        public var x: Double?
        public var y: Double?
        public var xSource: Vec2?
        public var ySource: Vec2?
        public var snapped: Bool { x != nil || y != nil }
    }

    /// Guides win over node alignment at similar distance; an axis that does not snap falls back
    /// to the grid (`grid > 0`).
    public static func snap(_ p: Vec2, guides: [GuideLine], alignWith nodes: [Vec2], tolerance: Double,
                            grid: Double) -> Result {
        var bestX: (v: Double, d: Double, src: Vec2?)?
        var bestY: (v: Double, d: Double, src: Vec2?)?
        for g in guides {
            let d = abs((g.isVertical ? p.x : p.y) - g.position)
            guard d <= tolerance else { continue }
            if g.isVertical { if d < (bestX?.d ?? .infinity) { bestX = (g.position, d * 0.5, nil) } }
            else if d < (bestY?.d ?? .infinity) { bestY = (g.position, d * 0.5, nil) }
        }
        for n in nodes {
            let dx = abs(p.x - n.x), dy = abs(p.y - n.y)
            if dx <= tolerance, dx < (bestX?.d ?? .infinity) { bestX = (n.x, dx, n) }
            if dy <= tolerance, dy < (bestY?.d ?? .infinity) { bestY = (n.y, dy, n) }
        }
        func g(_ v: Double) -> Double { grid > 0 ? (v / grid).rounded() * grid : v }
        let x = bestX?.v ?? g(p.x), y = bestY?.v ?? g(p.y)
        return Result(point: Vec2(x, y), x: bestX?.v, y: bestY?.v, xSource: bestX?.src, ySource: bestY?.src)
    }
}
