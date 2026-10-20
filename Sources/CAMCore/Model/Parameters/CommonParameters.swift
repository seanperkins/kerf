import Foundation

// All lengths are in document units; depths are measured DOWN from the material top
// (positive = into the material). Default values assume inches — the UI rescales them for
// millimetre documents (multiply by 25.4).

public enum CutDirection: String, Codable, CaseIterable, Sendable {
    case climb, conventional
}

public enum RampType: String, Codable, CaseIterable, Sendable {
    /// Linear zig-zag ramp along the path.
    case zigzag
    /// Spiral/helical descent following the path.
    case spiral
    /// Smooth ramp blended into the start of the cut.
    case smooth
}

public struct RampSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var type: RampType
    /// Horizontal ramp length (used by zigzag/smooth).
    public var length: Double
    /// Maximum ramp angle in degrees (limits steepness when length is too short).
    public var maxAngle: Double

    public init(isEnabled: Bool = false, type: RampType = .smooth, length: Double = 1.0, maxAngle: Double = 10) {
        self.isEnabled = isEnabled; self.type = type; self.length = length; self.maxAngle = maxAngle
    }
}

/// Depth range + per-pass stepdown shared by most operations.
public struct DepthSettings: Codable, Hashable, Sendable {
    public var startDepth: Double
    public var cutDepth: Double
    /// Max depth per pass; nil = use the tool's stepdown.
    public var passDepth: Double?
    /// Optional shallower final pass (0 = none).
    public var finalPassDepth: Double

    public init(startDepth: Double = 0, cutDepth: Double = 0.25, passDepth: Double? = nil, finalPassDepth: Double = 0) {
        self.startDepth = startDepth; self.cutDepth = cutDepth; self.passDepth = passDepth
        self.finalPassDepth = finalPassDepth
    }

    /// Pass depths from startDepth (exclusive) to cutDepth (inclusive), evenly spaced and
    /// never deeper than `stepdown` apart. Shared helper so every op paces passes the same way.
    public func passDepths(toolStepdown: Double) -> [Double] {
        let step = max(passDepth ?? toolStepdown, 1e-6)
        let total = cutDepth - startDepth
        guard total > 1e-12 else { return [] }
        let finalPass = finalPassDepth > 0 && finalPassDepth < total ? finalPassDepth : 0
        let roughTotal = total - finalPass
        let n = max(1, Int(ceil(roughTotal / step - 1e-9)))
        var depths = (1...n).map { startDepth + roughTotal * Double($0) / Double(n) }
        if finalPass > 0 { depths.append(cutDepth) }
        return depths
    }
}
