import Foundation

/// Side of a double-sided job. Each side's vectors are drawn in that face's own material
/// frame as seen from above while it faces up, so toolpaths need no extra transform.
public enum JobSide: String, Codable, CaseIterable, Sendable {
    case top, bottom

    public var other: JobSide { self == .top ? .bottom : .top }
}

/// How the stock is turned over between the two sides.
public enum FlipAxis: String, Codable, CaseIterable, Sendable {
    /// Turned over about the vertical (Y) centre line: X is mirrored.
    case leftRight
    /// Turned over about the horizontal (X) centre line: Y is mirrored.
    case topBottom
}

/// Double-sided job settings.
public struct TwoSidedSetup: Codable, Hashable, Sendable {
    public var flip: FlipAxis
    /// Z zero used for the bottom side (nil = same as the top side's `zZero`).
    public var bottomZZero: ZZeroMode?

    public init(flip: FlipAxis = .leftRight, bottomZZero: ZZeroMode? = nil) {
        self.flip = flip; self.bottomZZero = bottomZZero
    }
}

extension JobSetup {
    public var isTwoSided: Bool { twoSided != nil }

    /// Maps a point in one side's frame to the same physical point in the other side's frame
    /// (mirror about the material centre line of the flip axis). Its own inverse.
    public var otherSideTransform: Transform2D {
        switch twoSided?.flip ?? .leftRight {
        case .leftRight: return .mirror(horizontalAxis: false, about: Vec2(width / 2, 0))
        case .topBottom: return .mirror(horizontalAxis: true, about: Vec2(0, height / 2))
        }
    }

    /// Job used to machine `side`: identical except for the bottom side's Z zero override.
    public func forSide(_ side: JobSide) -> JobSetup {
        guard side == .bottom, let t = twoSided else { return self }
        var j = self
        j.zZero = t.bottomZZero ?? zZero
        return j
    }
}

extension Document {
    /// Side a shape is on (its layer's side; top when single-sided or unknown).
    public func side(of shape: Shape) -> JobSide {
        guard job.isTwoSided else { return .top }
        return layer(id: shape.layerID)?.side ?? .top
    }

    /// Side for a set of shapes: the common side, or nil when they are on both sides.
    public func side(ofShapes ids: [UUID]) -> JobSide? {
        let sides = Set(shapes(ids: ids).map { side(of: $0) })
        if sides.count > 1 { return nil }
        return sides.first ?? .top
    }
}
