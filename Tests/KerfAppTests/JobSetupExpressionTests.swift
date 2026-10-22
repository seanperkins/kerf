import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

/// Expressions typed into Job Setup evaluate against the form's pending values, and the link
/// they leave behind is re-evaluated against the committed job on Apply (issue #25).
@Suite @MainActor struct JobSetupExpressionTests {
    /// What a Job Setup field does on commit: parse with the form's variables, note the expression, write.
    static func type(_ text: String, into form: JobSetupForm, document: KerfDocument, current: Double) throws -> Double {
        let style = ExpressionNumberStyle(variables: form.variableTable(in: document.document), units: form.units,
                                          recorder: document.expressionRecorder)
        let v = try style.parseStrategy.parse(text)
        return document.expressionRecorder.valueToWrite(v, current: current)
    }

    @Test func expressionsSeeTheDraftThicknessAndStayRightAfterApply() throws {
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        #expect(doc.document.job.thickness == 0.75)
        var form = JobSetupForm(project: doc.project, machines: MachineCatalog.shared.machines)
        form.job.thickness = 0.5
        // Before Apply the saved thickness is still 0.75; the form's table says 0.5.
        #expect(form.variableTable(in: doc.document)["thickness"] == 0.5)
        #expect(doc.document.variableTable["thickness"] == 0.75)
        form.job.safeZ = try Self.type("=thickness/2", into: form, document: doc, current: form.job.safeZ)
        #expect(form.job.safeZ == 0.25)
        doc.applyJobSetup(form)
        // Applied: the value stands, and it is linked to the committed job.
        #expect(doc.document.job.thickness == 0.5 && doc.document.job.safeZ == 0.25)
        #expect(doc.document.linkedValues.map(\.expression) == ["=thickness/2"])
        #expect(doc.document.linkedValues.first?.path == ["safeZ"])
        // The link follows the material from now on.
        doc.perform("Thicker") { $0.document.job.thickness = 1.0 }
        #expect(doc.document.job.safeZ == 0.5)
    }

    @Test func userVariablesAndSwitchedUnitsReachTheForm() throws {
        var p = AppTestSupport.project()
        p.document.userVariables = [DocumentVariable(name: "margin", value: 0.1)]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        var form = JobSetupForm(project: doc.project, machines: MachineCatalog.shared.machines)
        #expect(form.variableTable(in: doc.document)["margin"] == 0.1)
        // Switching the form to millimetres scales the draft job, so `width` is in millimetres too.
        form.setUnits(.millimeter)
        #expect(abs((form.variableTable(in: doc.document)["width"] ?? 0) - 24 * 25.4) < 1e-9)
        #expect(try Self.type("=width/2", into: form, document: doc, current: 0) == 12 * 25.4)
    }
}
