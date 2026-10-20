import Foundation

/// Move / scale / rotate / mirror applied to a selection of shapes. Unless a pivot is given,
/// scaling, rotation and mirroring happen about the centre of the selection's bounds.
public enum ShapeTransforms {
    public static func move(_ shapes: [Shape], by delta: Vec2) -> [Shape] {
        apply(.translation(delta), to: shapes)
    }

    /// Move the selection so its bounds' lower-left corner lands on `point`.
    public static func move(_ shapes: [Shape], lowerLeftTo point: Vec2) -> [Shape] {
        let b = PathGeometry.bounds(of: shapes)
        guard !b.isEmpty else { return shapes }
        return move(shapes, by: point - b.min)
    }

    public static func scale(_ shapes: [Shape], sx: Double, sy: Double, about pivot: Vec2? = nil) -> [Shape] {
        apply(.scale(sx, sy, about: pivot ?? center(shapes)), to: shapes)
    }

    /// Scale so the selection's bounds become `width` x `height` (pass nil to keep aspect ratio
    /// from the other dimension). The lower-left corner of the bounds stays fixed.
    public static func resize(_ shapes: [Shape], width: Double?, height: Double?) -> [Shape] {
        let b = PathGeometry.bounds(of: shapes)
        guard !b.isEmpty else { return shapes }
        var sx = width.map { b.width > 0 ? $0 / b.width : 1 }
        var sy = height.map { b.height > 0 ? $0 / b.height : 1 }
        if sx == nil { sx = sy }
        if sy == nil { sy = sx }
        return scale(shapes, sx: sx ?? 1, sy: sy ?? 1, about: b.min)
    }

    /// Rotate counter-clockwise by `degrees`.
    public static func rotate(_ shapes: [Shape], degrees: Double, about pivot: Vec2? = nil) -> [Shape] {
        apply(.rotation(degrees * .pi / 180, about: pivot ?? center(shapes)), to: shapes)
    }

    public enum MirrorAxis: Sendable { case horizontal, vertical }

    /// `.horizontal` flips top-to-bottom (across a horizontal axis); `.vertical` flips
    /// left-to-right.
    public static func mirror(_ shapes: [Shape], axis: MirrorAxis, about pivot: Vec2? = nil) -> [Shape] {
        apply(.mirror(horizontalAxis: axis == .horizontal, about: pivot ?? center(shapes)), to: shapes)
    }

    public static func apply(_ t: Transform2D, to shapes: [Shape]) -> [Shape] {
        shapes.map { $0.isLocked ? $0 : $0.transformed(t) }
    }

    static func center(_ shapes: [Shape]) -> Vec2 {
        let b = PathGeometry.bounds(of: shapes)
        return b.isEmpty ? .zero : b.center
    }
}
