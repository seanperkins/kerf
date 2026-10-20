import Foundation
import Testing
@testable import CADCore

@Suite struct IOExpressionTests {
    let vars = ["thickness": 0.75, "width": 24.0, "rail": 2.5]

    func ev(_ s: String, units: LengthUnit? = nil) throws -> Double {
        try ExpressionEvaluator.evaluate(s, variables: vars, units: units)
    }

    @Test func arithmeticAndPrecedence() throws {
        #expect(try ev("1.5") == 1.5)
        #expect(try ev("1 + 2 * 3") == 7)
        #expect(try ev("(1 + 2) * 3") == 9)
        #expect(try ev("-2^2") == -4)
        #expect(try ev("2^3^2") == 512)
        #expect(try ev("10 / 4 - .5") == 2)
        #expect(try ev("1e-3 * 1000") == 1)
    }

    @Test func variablesAreCaseInsensitive() throws {
        #expect(try ev("=thickness") == 0.75)
        #expect(try ev("= Thickness/2 + RAIL") == 2.875)
        #expect(throws: ExpressionEvaluator.ExpressionError.unknownVariable("depth")) { try ev("depth") }
    }

    @Test func unitSuffixes() throws {
        #expect(abs(try ev("1/4in", units: .millimeter) - 6.35) < 1e-12)
        #expect(abs(try ev("25.4mm", units: .inch) - 1) < 1e-12)
        #expect(abs(try ev("2\" + 1cm", units: .millimeter) - 60.8) < 1e-12)
        // Without document units a suffix is just an unknown name.
        #expect(throws: ExpressionEvaluator.ExpressionError.self) { try ev("2in") }
        #expect(throws: ExpressionEvaluator.ExpressionError.self) { try ev("2 inner", units: .inch) }
    }

    @Test func errors() {
        #expect(throws: ExpressionEvaluator.ExpressionError.divisionByZero) { try ev("1/0") }
        #expect(throws: ExpressionEvaluator.ExpressionError.self) { try ev("(1+2") }
        #expect(throws: ExpressionEvaluator.ExpressionError.self) { try ev("1 +") }
        #expect(throws: ExpressionEvaluator.ExpressionError.self) { try ev("") }
    }

    @Test func documentTable() throws {
        var d = Document()
        #expect(d.variableTable["thickness"] == 0.75)
        d.userVariables = [DocumentVariable(name: "Gap", value: 0.1)]
        #expect(d.variableTable["gap"] == 0.1)
        let back = try JSONDecoder().decode(Document.self, from: JSONEncoder().encode(d))
        #expect(back.userVariables.map(\.name) == ["Gap"])
        #expect(DocumentVariable.isValidName("rail_2") && !DocumentVariable.isValidName("2rail") && !DocumentVariable.isValidName("a b"))
    }
}
