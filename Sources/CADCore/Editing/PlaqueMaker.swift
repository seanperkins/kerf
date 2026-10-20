import Foundation

/// Decorative plaque / sign outlines around a box (usually the text's bounds plus a margin).
public enum PlaqueMaker {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case rectangle, rounded, chamfered, notched, oval, ogee
    }

    /// Plaque outline around `box` with corner size `corner`. With `borderInset > 0` a second,
    /// inner border line follows the outline that far inside.
    public static func make(_ style: Style, box: Rect2, corner: Double, borderInset: Double = 0,
                            tolerance: Double = Path.defaultTolerance) -> [Path] {
        guard box.width > 0, box.height > 0 else { return [] }
        let c = max(0, min(corner, min(box.width, box.height) / 2 - 1e-9))
        let outline: Path
        switch style {
        case .rectangle: outline = ShapeFactory.rectangle(box)
        case .rounded: outline = ShapeFactory.rectangle(box, cornerRadius: c)
        case .chamfered: outline = CornerOps.apply(.chamfer(distance: c), to: ShapeFactory.rectangle(box))
        case .notched: outline = concaveCorners(box, radius: c)
        case .oval: outline = ShapeFactory.ellipse(center: box.center, rx: box.width / 2, ry: box.height / 2)
        case .ogee: outline = ogee(box, size: c)
        }
        var out = [outline]
        if borderInset > 0 {
            out += PathOps.offset([outline], by: -borderInset, join: .round, tolerance: tolerance)
        }
        return out
    }

    /// Rectangle with quarter-circle notches cut into each corner.
    static func concaveCorners(_ b: Rect2, radius r: Double) -> Path {
        guard r > 0 else { return ShapeFactory.rectangle(b) }
        let (x0, y0, x1, y1) = (b.min.x, b.min.y, b.max.x, b.max.y)
        return Path(start: Vec2(x0 + r, y0), segments: [
            .line(to: Vec2(x1 - r, y0)),
            .arc(to: Vec2(x1, y0 + r), center: Vec2(x1, y0), clockwise: true),
            .line(to: Vec2(x1, y1 - r)),
            .arc(to: Vec2(x1 - r, y1), center: Vec2(x1, y1), clockwise: true),
            .line(to: Vec2(x0 + r, y1)),
            .arc(to: Vec2(x0, y1 - r), center: Vec2(x0, y1), clockwise: true),
            .line(to: Vec2(x0, y0 + r)),
            .arc(to: Vec2(x0 + r, y0), center: Vec2(x0, y0), clockwise: true),
        ], isClosed: true)
    }

    /// Rectangle with S-curved (ogee) corners: a step in, then a quarter round out.
    static func ogee(_ b: Rect2, size s: Double) -> Path {
        guard s > 0 else { return ShapeFactory.rectangle(b) }
        let h = s / 2
        let (x0, y0, x1, y1) = (b.min.x, b.min.y, b.max.x, b.max.y)
        // Each corner: concave quarter of radius h, then convex quarter of radius h.
        return Path(start: Vec2(x0 + s, y0), segments: [
            .line(to: Vec2(x1 - s, y0)),
            .arc(to: Vec2(x1 - h, y0 + h), center: Vec2(x1 - s, y0 + h), clockwise: false),
            .arc(to: Vec2(x1, y0 + s), center: Vec2(x1, y0 + h), clockwise: true),
            .line(to: Vec2(x1, y1 - s)),
            .arc(to: Vec2(x1 - h, y1 - h), center: Vec2(x1 - h, y1 - s), clockwise: false),
            .arc(to: Vec2(x1 - s, y1), center: Vec2(x1 - h, y1), clockwise: true),
            .line(to: Vec2(x0 + s, y1)),
            .arc(to: Vec2(x0 + h, y1 - h), center: Vec2(x0 + s, y1 - h), clockwise: false),
            .arc(to: Vec2(x0, y1 - s), center: Vec2(x0, y1 - h), clockwise: true),
            .line(to: Vec2(x0, y0 + s)),
            .arc(to: Vec2(x0 + h, y0 + h), center: Vec2(x0 + h, y0 + s), clockwise: false),
            .arc(to: Vec2(x0 + s, y0), center: Vec2(x0 + h, y0), clockwise: true),
        ], isClosed: true)
    }
}
