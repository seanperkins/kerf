import Foundation

/// 2D point / vector in document units.
public struct Vec2: Codable, Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }
    public var normalized: Vec2 { let l = length; return l > 0 ? Vec2(x / l, y / l) : .zero }
    /// Perpendicular rotated +90° (counter-clockwise).
    public var perpendicular: Vec2 { Vec2(-y, x) }
    public var angle: Double { atan2(y, x) }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    public func distance(to o: Vec2) -> Double { (self - o).length }
    public func lerp(to o: Vec2, _ t: Double) -> Vec2 { self + (o - self) * t }
    public func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }
    public func isApproximatelyEqual(to o: Vec2, tolerance: Double = 1e-9) -> Bool {
        abs(x - o.x) <= tolerance && abs(y - o.y) <= tolerance
    }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    public static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    public var description: String { "(\(x), \(y))" }
}

/// 3D point / vector. In toolpaths, Z is machine Z (see `MachineCoordinates` in CAMCore).
public struct Vec3: Codable, Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    public init(_ xy: Vec2, z: Double) { self.x = xy.x; self.y = xy.y; self.z = z }

    public static let zero = Vec3(0, 0, 0)

    public var xy: Vec2 { Vec2(x, y) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: Vec3 { let l = length; return l > 0 ? self / l : .zero }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }
    public func distance(to o: Vec3) -> Double { (self - o).length }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    public static func / (a: Vec3, s: Double) -> Vec3 { Vec3(a.x / s, a.y / s, a.z / s) }

    public var description: String { "(\(x), \(y), \(z))" }
}
