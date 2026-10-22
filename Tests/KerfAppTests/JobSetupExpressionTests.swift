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

    @Test func userVariablesAndSwitchedUnitsReachTheFormInTheFormsUnits() throws {
        var p = AppTestSupport.project()
        p.document.userVariables = [DocumentVariable(name: "margin", value: 0.1)]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        var form = JobSetupForm(project: doc.project, machines: MachineCatalog.shared.machines)
        #expect(form.variableTable(in: doc.document)["margin"] == 0.1)
        // Switching the form to millimetres scales the draft job; the table gives the user variable in
        // millimetres too, so the two scales never meet in one expression.
        form.setUnits(.millimeter)
        let table = form.variableTable(in: doc.document)
        #expect(abs((table["width"] ?? 0) - 24 * 25.4) < 1e-9 && abs((table["margin"] ?? 0) - 2.54) < 1e-9)
        form.job.height = try Self.type("=width/2 + margin", into: form, document: doc, current: form.job.height)
        #expect(abs(form.job.height - (12 * 25.4 + 2.54)) < 1e-9)
        // A suffix converts into the form's units, not the saved document's.
        #expect(abs(try Self.type("1/4in", into: form, document: doc, current: 0) - 6.35) < 1e-9)
        // Applying converts the project and still links the expression, typed in the new units.
        doc.applyJobSetup(form)
        #expect(doc.units == .millimeter && abs(doc.document.job.height - (12 * 25.4 + 2.54)) < 1e-9)
        #expect(doc.document.userVariables.map(\.value) == [2.54])
        #expect(doc.document.linkedValues.map { ($0.expression, $0.path) }.contains { $0 == "=width/2 + margin" && $1 == ["height"] })
        doc.perform("Wider") { $0.document.job.width = 400 }
        #expect(abs(doc.document.job.height - 202.54) < 1e-9)
    }

    @Test func aCancelledSheetDropsItsTypedExpressions() throws {
        var p = AppTestSupport.project()
        let op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [p.document.shapes[0].id])!
        p.operations = [op]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        var form = JobSetupForm(project: doc.project, machines: MachineCatalog.shared.machines)
        form.job.safeZ = try Self.type("=thickness/2", into: form, document: doc, current: form.job.safeZ)
        #expect(doc.expressionRecorder.pending.count == 1)
        // Cancel: the sheet closes without applying, and the expression is forgotten.
        doc.sheetDismissed()
        #expect(doc.expressionRecorder.pending.isEmpty)
        // A later edit that happens to take the same value is not linked to it.
        guard case .profile(var profile) = doc.operation(op.id) else { throw TestError.notAProfile }
        profile.params.depth.cutDepth = 0.375
        doc.updateOperation(.profile(profile))
        #expect(doc.document.linkedValues.isEmpty)
    }

    @Test func aFieldIsNeverLinkedToAnExpressionOfItself() throws {
        // `=thickness/2` typed into Thickness halves it once; linking it would halve it again on
        // every later edit. The value is kept and no link is made.
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        var form = JobSetupForm(project: doc.project, machines: MachineCatalog.shared.machines)
        form.job.thickness = try Self.type("=thickness/2", into: form, document: doc, current: form.job.thickness)
        #expect(form.job.thickness == 0.375)
        doc.applyJobSetup(form)
        #expect(doc.document.job.thickness == 0.375 && doc.document.linkedValues.isEmpty)
        doc.perform("Unrelated") { $0.document.job.width = 30 }
        #expect(doc.document.job.thickness == 0.375)
        // Also an existing self-link from an older file: dropped, and the value no longer moves.
        doc.perform("Stale link") {
            $0.document.linkedValues = [VariableLink(target: .job(sheetID: $0.document.currentSheetID), path: ["safeZ"], expression: "=safez*2")]
        }
        #expect(doc.document.linkedValues.isEmpty)
        #expect(VariableLink.references("safez", in: "=safeZ*2", variables: doc.document.variableTable, units: .inch))
        #expect(!VariableLink.references("safez", in: "=thickness/2", variables: doc.document.variableTable, units: .inch))
    }

    enum TestError: Error { case notAProfile }
}
