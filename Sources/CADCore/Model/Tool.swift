import Foundation

public enum ToolKind: String, Codable, CaseIterable, Sendable {
    case endMill
    case ballNose
    case vBit
    case engraving
    case drill

    public var displayName: String {
        switch self {
        case .endMill: return "End Mill"
        case .ballNose: return "Ball Nose"
        case .vBit: return "V-Bit"
        case .engraving: return "Engraving"
        case .drill: return "Drill"
        }
    }
}

/// A cutting tool with its cutting data. All lengths in `units`; feeds in `units`/min.
public struct Tool: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ToolKind
    public var units: LengthUnit
    /// Machine tool number (T word).
    public var number: Int
    public var diameter: Double
    public var flutes: Int
    /// Included angle in degrees (V-bit / engraving).
    public var angle: Double?
    /// Flat tip diameter (engraving / flat-tipped V-bits), 0 for a sharp V.
    public var tipDiameter: Double
    public var fluteLength: Double?
    public var stepdown: Double
    /// Stepover as a distance (not a percentage).
    public var stepover: Double
    public var spindleRPM: Double
    public var feedRate: Double
    public var plungeRate: Double
    public var notes: String

    public init(id: UUID = UUID(), name: String, kind: ToolKind, units: LengthUnit = .inch,
                number: Int = 1, diameter: Double, flutes: Int = 2, angle: Double? = nil,
                tipDiameter: Double = 0, fluteLength: Double? = nil, stepdown: Double,
                stepover: Double, spindleRPM: Double = 18000, feedRate: Double, plungeRate: Double,
                notes: String = "") {
        self.id = id; self.name = name; self.kind = kind; self.units = units; self.number = number
        self.diameter = diameter; self.flutes = flutes; self.angle = angle
        self.tipDiameter = tipDiameter; self.fluteLength = fluteLength
        self.stepdown = stepdown; self.stepover = stepover; self.spindleRPM = spindleRPM
        self.feedRate = feedRate; self.plungeRate = plungeRate; self.notes = notes
    }

    public var radius: Double { diameter / 2 }

    /// Same tool with all lengths/feeds converted to `target` units.
    public func converted(to target: LengthUnit) -> Tool {
        guard target != units else { return self }
        let f = units.factor(to: target)
        var t = self
        t.units = target
        t.diameter *= f; t.tipDiameter *= f; t.fluteLength = fluteLength.map { $0 * f }
        t.stepdown *= f; t.stepover *= f; t.feedRate *= f; t.plungeRate *= f
        return t
    }

    /// For V-bits: cutting width at `depth` below the tip (geometry only).
    public func vWidth(atDepth depth: Double) -> Double {
        guard let a = angle, a > 0, a < 180 else { return diameter }
        return min(diameter, tipDiameter + 2 * depth * tan(a / 2 * .pi / 180))
    }

    /// For V-bits: depth at which the cutting width equals `width`.
    public func vDepth(forWidth width: Double) -> Double {
        guard let a = angle, a > 0, a < 180 else { return 0 }
        return max(0, (width - tipDiameter) / 2 / tan(a / 2 * .pi / 180))
    }
}
