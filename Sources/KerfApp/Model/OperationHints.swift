import CADCore
import CAMCore
import Foundation

/// Short explanatory lines shown under toolpath forms.
enum OperationHints {
    /// "3 pecks per hole: 0.125, 0.25, 0.375" style summary.
    static func peckSummary(_ p: DrillParameters, units: LengthUnit) -> String {
        guard p.cutDepth > p.startDepth else { return "Cut depth must be deeper than the start depth." }
        let depths = DrillOperation.peckDepths(start: p.startDepth, end: p.cutDepth, peck: p.peckDepth)
        if depths.count == 1 { return "Single plunge to \(RulerTicks.label(p.cutDepth)) \(units.abbreviation)." }
        let list = depths.map { RulerTicks.label(($0 * 1000).rounded() / 1000) }.joined(separator: ", ")
        return "\(depths.count) pecks per hole: \(list) \(units.abbreviation)."
    }

    /// Why a pocket's clearance tool would be ignored (nil when it will be used or none is set).
    static func pocketClearanceProblem(finish: Tool?, clearance: Tool?) -> String? {
        guard let c = clearance else { return nil }
        guard let f = finish else { return "Choose a finish tool." }
        if c.id == f.id { return "The clearance tool is the finish tool; it will be ignored." }
        if c.diameter * c.units.factor(to: .inch) <= f.diameter * f.units.factor(to: .inch) + 1e-9 { return "The clearance tool must be larger than the finish tool; it will be ignored." }
        return nil
    }
}
