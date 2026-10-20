import CADCore
import Foundation

/// Chip-load arithmetic for the feeds and speeds calculator. Lengths are in `units`, feeds in
/// units per minute.
public enum FeedsAndSpeeds {
    /// Feed rate = RPM × flutes × chip load (chip load = advance per tooth).
    public static func feedRate(rpm: Double, flutes: Int, chipLoad: Double) -> Double {
        max(rpm, 0) * Double(max(flutes, 1)) * max(chipLoad, 0)
    }

    /// Chip load = feed / (RPM × flutes).
    public static func chipLoad(feedRate: Double, rpm: Double, flutes: Int) -> Double {
        let teeth = max(rpm, 0) * Double(max(flutes, 1))
        return teeth > 0 ? max(feedRate, 0) / teeth : 0
    }

    /// RPM needed for `feedRate` at `chipLoad`.
    public static func rpm(feedRate: Double, flutes: Int, chipLoad: Double) -> Double {
        let perRev = Double(max(flutes, 1)) * max(chipLoad, 0)
        return perRev > 0 ? max(feedRate, 0) / perRev : 0
    }

    /// Cutting-edge surface speed: feet per minute for inch tools, metres per minute for mm.
    public static func surfaceSpeed(diameter: Double, rpm: Double, units: LengthUnit) -> Double {
        let circumference = Double.pi * max(diameter, 0) * max(rpm, 0)
        return units == .inch ? circumference / 12 : circumference / 1000
    }

    /// Unit label for `surfaceSpeed`.
    public static func surfaceSpeedUnit(_ units: LengthUnit) -> String { units == .inch ? "SFM" : "m/min" }
}
