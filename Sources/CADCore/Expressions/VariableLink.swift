import Foundation

/// A numeric parameter that stays tied to the expression typed into it (`=thickness`,
/// `=rail*2`): when variables or the material change, the parameter is re-evaluated.
/// The parameter is addressed by its key path in the target's JSON encoding.
public struct VariableLink: Codable, Hashable, Identifiable, Sendable {
    public enum Target: Codable, Hashable, Sendable {
        /// The job setup of a material sheet (`MaterialSheet.primaryID` for the first sheet).
        case job(sheetID: UUID)
        /// A toolpath's settings.
        case operation(UUID)
    }

    public var id: UUID
    public var target: Target
    /// JSON key path (object keys, array indices as decimal strings).
    public var path: [String]
    public var expression: String

    public init(id: UUID = UUID(), target: Target, path: [String], expression: String) {
        self.id = id; self.target = target; self.path = path; self.expression = expression
    }

    /// True when the expression uses a name (a variable), not just numbers and units.
    public static func usesVariables(_ expression: String, units: LengthUnit?) -> Bool {
        do {
            _ = try ExpressionEvaluator.evaluate(expression, variables: [:], units: units)
            return false
        } catch ExpressionEvaluator.ExpressionError.unknownVariable {
            return true
        } catch {
            return false
        }
    }
}

extension Document {
    public var linkedValues: [VariableLink] {
        get { variableLinks ?? [] }
        set { variableLinks = newValue.isEmpty ? nil : newValue }
    }

    /// Expression names for one sheet's material (`variableTable` with that sheet's job).
    public func variableTable(forSheet id: UUID) -> [String: Double] {
        guard let j = job(ofSheet: id), id != currentSheetID else { return variableTable }
        var d = self
        d.job = j
        return d.variableTable
    }
}
