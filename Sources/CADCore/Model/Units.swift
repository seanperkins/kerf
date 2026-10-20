import Foundation

public enum LengthUnit: String, Codable, CaseIterable, Sendable {
    case inch
    case millimeter

    /// Millimetres per one of this unit.
    public var millimeters: Double { self == .inch ? 25.4 : 1 }

    /// Multiply a value in `self` by this factor to get `target` units.
    public func factor(to target: LengthUnit) -> Double { millimeters / target.millimeters }

    public func convert(_ value: Double, to target: LengthUnit) -> Double { value * factor(to: target) }

    public var abbreviation: String { self == .inch ? "in" : "mm" }
}
