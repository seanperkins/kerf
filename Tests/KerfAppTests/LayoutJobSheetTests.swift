import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

@Suite struct LayoutJobSheetTests {
    /// Pocket + profile on two different tools, calculated.
    func calculatedDoc(zZero: ZZeroMode = .materialTop, origin: XYOrigin = .lowerLeft) -> KerfDocument {
        var p = AppTestSupport.project()
        p.document.name = "Sign <1>"
        p.document.job.zZero = zZero
        p.document.job.xyOrigin = origin
        let lib = ToolLibrary.seeded
        let a = p.document.shapes[0].id, b = p.document.shapes[1].id
        p.operations = [
            OperationFactory.make(kind: .pocket, project: p, library: lib, shapeIDs: [a])!,
            OperationFactory.make(kind: .profile, project: p, library: lib, shapeIDs: [a, b])!,
        ]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        doc.calculateNow(doc.project.operations.map(\.id))
        return doc
    }

    @Test func listsSetupToolsAndStepsInProgramOrder() {
        let doc = calculatedDoc()
        let js = doc.makeJobSheet(date: Date(timeIntervalSince1970: 0))
        #expect(js.steps.count >= 2)
        #expect(js.steps.first?.toolChange == true)
        #expect(js.steps.map(\.index) == Array(1...js.steps.count))
        #expect(js.steps.last?.kind == OperationKind.profile.displayName)
        // Profile cuts through the 0.75" material.
        #expect(js.steps.last?.maxDepth == "0.75 in")
        #expect(!js.tools.isEmpty)
        #expect(js.tools.allSatisfy { !$0.usedBy.isEmpty })
        #expect(js.zZeroInstruction.contains("TOP"))
        #expect(js.xyOriginInstruction.contains("lower-left"))
        #expect(js.warnings.isEmpty)
        #expect(js.sheets.count == 1)
        #expect(js.sheets[0].shapes.count == 2)
    }

    @Test func describesSpoilboardZeroAndCentreOrigin() {
        let js = calculatedDoc(zZero: .spoilboard, origin: .center).makeJobSheet()
        #expect(js.zZeroInstruction.contains("SPOILBOARD"))
        #expect(js.xyOriginInstruction.contains("centre"))
        #expect(js.origin == Vec2(12, 9))
    }

    @Test func uncalculatedToolpathsAreWarned() {
        var p = AppTestSupport.project()
        p.operations = [OperationFactory.make(kind: .profile, project: p, library: .seeded,
                                              shapeIDs: [p.document.shapes[0].id])!]
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        let js = doc.makeJobSheet()
        #expect(js.steps.isEmpty)
        #expect(js.warnings.count == 1)
    }

    @Test func htmlIsEscapedAndHasThePreview() {
        let html = JobSheetHTML.render(calculatedDoc().makeJobSheet())
        #expect(html.hasPrefix("<!doctype html>"))
        #expect(html.contains("Sign &lt;1&gt;"))
        #expect(!html.contains("Sign <1>"))
        #expect(html.contains("<svg"))
        #expect(html.contains("X0 Y0"))
        #expect(html.contains("Toolpath order"))
    }
}
