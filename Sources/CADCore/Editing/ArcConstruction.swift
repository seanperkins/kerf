import Foundation

/// Circular arcs from drawing input.
public enum ArcConstruction {
    /// Arc from `start` to `end` passing through `through` (3-point arc). Nil when the points are
    /// collinear or coincide.
    public static func threePoint(start a: Vec2, end b: Vec2, through m: Vec2) -> Path? {
        guard let c = circumcenter(a, m, b) else { return nil }
        // Counter-clockwise from a to b passes m?  Then the arc is CCW.
        let ccw = Dogbone.ccwArcContains(from: a, to: b, center: c, point: m)
        return Path(start: a, segments: [.arc(to: b, center: c, clockwise: !ccw)], isClosed: false)
    }

    /// Arc around `center` starting at `start` (which sets the radius) and ending on the ray
    /// towards `endDirection`; counter-clockwise unless `clockwise`.
    public static func centerStartEnd(center c: Vec2, start a: Vec2, endDirection e: Vec2, clockwise: Bool = false) -> Path? {
        let r = a.distance(to: c)
        let dir = e - c
        guard r > 1e-12, dir.length > 1e-12 else { return nil }
        let b = c + dir.normalized * r
        guard !b.isApproximatelyEqual(to: a, tolerance: r * 1e-9) else { return nil }
        return Path(start: a, segments: [.arc(to: b, center: c, clockwise: clockwise)], isClosed: false)
    }

    /// Arc by centre, radius and start/end angles in degrees; it sweeps counter-clockwise when
    /// `endDegrees > startDegrees`, clockwise otherwise. A 360° sweep gives a closed circle.
    public static func centerAngles(center c: Vec2, radius r: Double, startDegrees: Double, endDegrees: Double) -> Path? {
        guard r > 0, abs(endDegrees - startDegrees) > 1e-9 else { return nil }
        let a0 = startDegrees * .pi / 180, a1 = endDegrees * .pi / 180
        let a = c + Vec2(cos(a0), sin(a0)) * r, b = c + Vec2(cos(a1), sin(a1)) * r
        if abs(abs(endDegrees - startDegrees) - 360) < 1e-9 || a.isApproximatelyEqual(to: b, tolerance: r * 1e-9) {
            // Full circle: two half arcs keep the start and end distinct.
            let mid = c + (c - a)
            return Path(start: a, segments: [.arc(to: mid, center: c, clockwise: false), .arc(to: a, center: c, clockwise: false)],
                        isClosed: true)
        }
        return Path(start: a, segments: [.arc(to: b, center: c, clockwise: endDegrees < startDegrees)], isClosed: false)
    }

    /// Centre of the circle through three points (nil when collinear).
    public static func circumcenter(_ a: Vec2, _ b: Vec2, _ c: Vec2) -> Vec2? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let scale = max((b - a).lengthSquared, (c - a).lengthSquared, 1e-300)
        guard abs(d) > 1e-12 * scale else { return nil }
        let a2 = a.lengthSquared, b2 = b.lengthSquared, c2 = c.lengthSquared
        return Vec2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                    (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
    }
}
