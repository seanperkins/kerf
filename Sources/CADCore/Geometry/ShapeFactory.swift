import Foundation

/// Parametric primitives as closed paths (counter-clockwise), in document units.
public enum ShapeFactory {
    public static func rectangle(_ r: Rect2, cornerRadius: Double = 0) -> Path {
        let rad = min(max(cornerRadius, 0), min(r.width, r.height) / 2)
        if rad <= 0 {
            return Path(points: [r.min, Vec2(r.max.x, r.min.y), r.max, Vec2(r.min.x, r.max.y)], closed: true)
        }
        let (x0, y0, x1, y1) = (r.min.x, r.min.y, r.max.x, r.max.y)
        return Path(start: Vec2(x0 + rad, y0), segments: [
            .line(to: Vec2(x1 - rad, y0)),
            .arc(to: Vec2(x1, y0 + rad), center: Vec2(x1 - rad, y0 + rad), clockwise: false),
            .line(to: Vec2(x1, y1 - rad)),
            .arc(to: Vec2(x1 - rad, y1), center: Vec2(x1 - rad, y1 - rad), clockwise: false),
            .line(to: Vec2(x0 + rad, y1)),
            .arc(to: Vec2(x0, y1 - rad), center: Vec2(x0 + rad, y1 - rad), clockwise: false),
            .line(to: Vec2(x0, y0 + rad)),
            .arc(to: Vec2(x0 + rad, y0), center: Vec2(x0 + rad, y0 + rad), clockwise: false),
        ], isClosed: true)
    }

    /// Circle as two semicircular arcs.
    public static func circle(center c: Vec2, radius r: Double) -> Path {
        Path(start: c + Vec2(r, 0), segments: [
            .arc(to: c - Vec2(r, 0), center: c, clockwise: false),
            .arc(to: c + Vec2(r, 0), center: c, clockwise: false),
        ], isClosed: true)
    }

    /// Ellipse as four cubic Béziers.
    public static func ellipse(center c: Vec2, rx: Double, ry: Double) -> Path {
        let k = 0.5522847498307936
        return Path(start: c + Vec2(rx, 0), segments: [
            .cubic(to: c + Vec2(0, ry), control1: c + Vec2(rx, ry * k), control2: c + Vec2(rx * k, ry)),
            .cubic(to: c + Vec2(-rx, 0), control1: c + Vec2(-rx * k, ry), control2: c + Vec2(-rx, ry * k)),
            .cubic(to: c + Vec2(0, -ry), control1: c + Vec2(-rx, -ry * k), control2: c + Vec2(-rx * k, -ry)),
            .cubic(to: c + Vec2(rx, 0), control1: c + Vec2(rx * k, -ry), control2: c + Vec2(rx, -ry * k)),
        ], isClosed: true)
    }

    /// Regular polygon with a vertex at angle `rotation` (radians, 0 = +X).
    public static func polygon(center c: Vec2, radius r: Double, sides: Int, rotation: Double = .pi / 2) -> Path {
        let n = max(3, sides)
        let pts = (0..<n).map { i in c + Vec2(cos(rotation + 2 * .pi * Double(i) / Double(n)),
                                               sin(rotation + 2 * .pi * Double(i) / Double(n))) * r }
        return Path(points: pts, closed: true)
    }

    public static func star(center c: Vec2, points: Int, outerRadius ro: Double, innerRadius ri: Double,
                            rotation: Double = .pi / 2) -> Path {
        let n = max(2, points)
        let pts = (0..<(2 * n)).map { i -> Vec2 in
            let a = rotation + .pi * Double(i) / Double(n)
            return c + Vec2(cos(a), sin(a)) * (i.isMultiple(of: 2) ? ro : ri)
        }
        return Path(points: pts, closed: true)
    }
}
