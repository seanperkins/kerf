import Foundation

/// Align and distribute helpers. Each shape moves as a whole (translation only).
public enum Alignment {
    public enum Edge: String, CaseIterable, Sendable {
        case left, right, top, bottom, centerHorizontal, centerVertical, center
    }

    /// Align shapes to `reference` (default: the union bounds of the selection).
    /// `centerHorizontal` aligns centre X values; `centerVertical` aligns centre Y values.
    public static func align(_ shapes: [Shape], _ edge: Edge, to reference: Rect2? = nil) -> [Shape] {
        let ref = reference ?? PathGeometry.bounds(of: shapes)
        guard !ref.isEmpty else { return shapes }
        return shapes.map { s in
            let b = s.bounds()
            guard !b.isEmpty, !s.isLocked else { return s }
            var d = Vec2.zero
            switch edge {
            case .left: d.x = ref.min.x - b.min.x
            case .right: d.x = ref.max.x - b.max.x
            case .bottom: d.y = ref.min.y - b.min.y
            case .top: d.y = ref.max.y - b.max.y
            case .centerHorizontal: d.x = ref.center.x - b.center.x
            case .centerVertical: d.y = ref.center.y - b.center.y
            case .center: d = ref.center - b.center
            }
            return s.transformed(.translation(d))
        }
    }

    /// Centre the selection (as a group) in `rect`, e.g. the material.
    public static func centerGroup(_ shapes: [Shape], in rect: Rect2) -> [Shape] {
        let b = PathGeometry.bounds(of: shapes)
        guard !b.isEmpty else { return shapes }
        return ShapeTransforms.move(shapes, by: rect.center - b.center)
    }

    public enum Axis: Sendable { case horizontal, vertical }

    /// Distribute with equal gaps between neighbours; the two extreme shapes stay put.
    /// Result is in the same order as the input.
    public static func distributeSpacing(_ shapes: [Shape], along axis: Axis) -> [Shape] {
        guard shapes.count > 2 else { return shapes }
        let boxes = shapes.map { $0.bounds() }
        let order = shapes.indices.sorted { lo(boxes[$0], axis) < lo(boxes[$1], axis) }
        let first = boxes[order.first!], last = boxes[order.last!]
        let total = hi(last, axis) - lo(first, axis)
        let sizes = order.map { size(boxes[$0], axis) }.reduce(0, +)
        let gap = (total - sizes) / Double(shapes.count - 1)
        var out = shapes
        var cursor = lo(first, axis)
        for i in order {
            let delta = cursor - lo(boxes[i], axis)
            out[i] = shapes[i].transformed(.translation(axis == .horizontal ? Vec2(delta, 0) : Vec2(0, delta)))
            cursor += size(boxes[i], axis) + gap
        }
        return out
    }

    /// Distribute so shape centres are equally spaced; the extreme shapes stay put.
    public static func distributeCenters(_ shapes: [Shape], along axis: Axis) -> [Shape] {
        guard shapes.count > 2 else { return shapes }
        let boxes = shapes.map { $0.bounds() }
        func c(_ b: Rect2) -> Double { axis == .horizontal ? b.center.x : b.center.y }
        let order = shapes.indices.sorted { c(boxes[$0]) < c(boxes[$1]) }
        let c0 = c(boxes[order.first!]), c1 = c(boxes[order.last!])
        let step = (c1 - c0) / Double(shapes.count - 1)
        var out = shapes
        for (k, i) in order.enumerated() {
            let delta = c0 + step * Double(k) - c(boxes[i])
            out[i] = shapes[i].transformed(.translation(axis == .horizontal ? Vec2(delta, 0) : Vec2(0, delta)))
        }
        return out
    }

    private static func lo(_ b: Rect2, _ a: Axis) -> Double { a == .horizontal ? b.min.x : b.min.y }
    private static func hi(_ b: Rect2, _ a: Axis) -> Double { a == .horizontal ? b.max.x : b.max.y }
    private static func size(_ b: Rect2, _ a: Axis) -> Double { a == .horizontal ? b.width : b.height }
}
