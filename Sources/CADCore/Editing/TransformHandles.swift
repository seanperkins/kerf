import Foundation

/// The interactive handles around a selection's bounding box and the transform each drag makes.
public enum TransformHandle: String, CaseIterable, Hashable, Sendable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left
    case rotate

    /// Unit position inside the box: (0,0) = lower-left, (1,1) = upper-right.
    public var unit: Vec2 {
        switch self {
        case .bottomLeft: return Vec2(0, 0)
        case .bottom: return Vec2(0.5, 0)
        case .bottomRight: return Vec2(1, 0)
        case .right: return Vec2(1, 0.5)
        case .topRight: return Vec2(1, 1)
        case .top: return Vec2(0.5, 1)
        case .topLeft: return Vec2(0, 1)
        case .left: return Vec2(0, 0.5)
        case .rotate: return Vec2(0.5, 1)
        }
    }

    /// The handle on the opposite side (fixed anchor while scaling).
    public var opposite: TransformHandle {
        switch self {
        case .bottomLeft: return .topRight
        case .bottom: return .top
        case .bottomRight: return .topLeft
        case .right: return .left
        case .topRight: return .bottomLeft
        case .top: return .bottom
        case .topLeft: return .bottomRight
        case .left: return .right
        case .rotate: return .rotate
        }
    }

    public var isCorner: Bool { [.bottomLeft, .bottomRight, .topRight, .topLeft].contains(self) }
    /// Edge handles scale in one axis only.
    public var scalesX: Bool { unit.x != 0.5 }
    public var scalesY: Bool { unit.y != 0.5 }
}

public enum TransformHandles {
    /// Handle positions in document units. The rotate handle sits `rotateOffset` above the top.
    public static func positions(for box: Rect2, rotateOffset: Double) -> [TransformHandle: Vec2] {
        var out: [TransformHandle: Vec2] = [:]
        for h in TransformHandle.allCases {
            out[h] = point(box, h.unit)
        }
        out[.rotate] = point(box, Vec2(0.5, 1)) + Vec2(0, rotateOffset)
        return out
    }

    /// Handle under `q` within `tolerance` (rotate handle wins ties because it sits apart).
    public static func hit(_ q: Vec2, box: Rect2, rotateOffset: Double, tolerance: Double) -> TransformHandle? {
        positions(for: box, rotateOffset: rotateOffset)
            .filter { $0.value.distance(to: q) <= tolerance }
            .min { $0.value.distance(to: q) < $1.value.distance(to: q) }?.key
    }

    /// Transform for dragging `handle` of `box` from `start` to `current` (document units).
    /// - keepAspect: corners scale uniformly (Shift).
    /// - fromCenter: scale about the box centre instead of the opposite handle (Option).
    /// - angleSnap: rotation snaps to multiples of this many degrees (0 = free).
    public static func transform(dragging handle: TransformHandle, box: Rect2, from start: Vec2, to current: Vec2,
                                 keepAspect: Bool, fromCenter: Bool, angleSnap: Double = 0) -> Transform2D {
        guard !box.isEmpty else { return .identity }
        if handle == .rotate {
            let c = box.center
            var a = (current - c).angle - (start - c).angle
            if angleSnap > 0 {
                let step = angleSnap * .pi / 180
                a = (a / step).rounded() * step
            }
            return .rotation(a, about: c)
        }
        let pivot = fromCenter ? box.center : point(box, handle.opposite.unit)
        let grip = point(box, handle.unit)
        let moved = grip + (current - start)
        var sx = 1.0, sy = 1.0
        if handle.scalesX, abs(grip.x - pivot.x) > 1e-12 { sx = (moved.x - pivot.x) / (grip.x - pivot.x) }
        if handle.scalesY, abs(grip.y - pivot.y) > 1e-12 { sy = (moved.y - pivot.y) / (grip.y - pivot.y) }
        if keepAspect && handle.isCorner {
            let s = abs(sx) > abs(sy) ? sx : sy
            sx = s; sy = s
        }
        // Avoid collapsing to zero (keeps the transform invertible).
        sx = abs(sx) < 1e-6 ? (sx < 0 ? -1e-6 : 1e-6) : sx
        sy = abs(sy) < 1e-6 ? (sy < 0 ? -1e-6 : 1e-6) : sy
        return .scale(sx, sy, about: pivot)
    }

    static func point(_ b: Rect2, _ u: Vec2) -> Vec2 {
        Vec2(b.min.x + b.width * u.x, b.min.y + b.height * u.y)
    }
}
