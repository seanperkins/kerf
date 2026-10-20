import Foundation

/// Axis-aligned bounding rectangle. `Rect2.empty` is the identity for `union`.
public struct Rect2: Codable, Hashable, Sendable {
    public var min: Vec2
    public var max: Vec2

    public init(min: Vec2, max: Vec2) { self.min = min; self.max = max }
    public init(x: Double, y: Double, width: Double, height: Double) {
        min = Vec2(x, y); max = Vec2(x + width, y + height)
    }
    public init(points: some Sequence<Vec2>) {
        var r = Rect2.empty
        for p in points { r.include(p) }
        self = r
    }

    public static let empty = Rect2(min: Vec2(.infinity, .infinity), max: Vec2(-.infinity, -.infinity))

    public var isEmpty: Bool { min.x > max.x || min.y > max.y }
    public var width: Double { isEmpty ? 0 : max.x - min.x }
    public var height: Double { isEmpty ? 0 : max.y - min.y }
    public var size: Vec2 { Vec2(width, height) }
    public var center: Vec2 { (min + max) * 0.5 }

    public mutating func include(_ p: Vec2) {
        min = Vec2(Swift.min(min.x, p.x), Swift.min(min.y, p.y))
        max = Vec2(Swift.max(max.x, p.x), Swift.max(max.y, p.y))
    }
    public func union(_ o: Rect2) -> Rect2 {
        if isEmpty { return o }
        if o.isEmpty { return self }
        return Rect2(min: Vec2(Swift.min(min.x, o.min.x), Swift.min(min.y, o.min.y)),
                     max: Vec2(Swift.max(max.x, o.max.x), Swift.max(max.y, o.max.y)))
    }
    public func contains(_ p: Vec2) -> Bool {
        p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y
    }
    public func intersects(_ o: Rect2) -> Bool {
        !(o.min.x > max.x || o.max.x < min.x || o.min.y > max.y || o.max.y < min.y)
    }
    public func insetBy(_ d: Double) -> Rect2 {
        Rect2(min: min + Vec2(d, d), max: max - Vec2(d, d))
    }
}
