import CADCore
import CAMCore
import Foundation
import Testing
@testable import LoftLineApp

@Suite @MainActor struct IOVariableLinkTests {
    static func setup() -> (LoftLineDocument, UUID) {
        var p = AppTestSupport.project()
        let op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [p.document.shapes[0].id])!
        p.operations = [op]
        return (LoftLineDocument(project: p, toolLibrary: AppTestSupport.library()), op.id)
    }

    static func cutDepth(_ d: LoftLineDocument, _ id: UUID) -> Double {
        guard case .profile(let o) = d.operation(id) else { return .nan }
        return o.params.depth.cutDepth
    }

    static func setCutDepth(_ d: LoftLineDocument, _ id: UUID, _ v: Double) {
        guard case .profile(var o) = d.operation(id) else { return }
        o.params.depth.cutDepth = v
        d.updateOperation(.profile(o))
    }

    /// What a numeric field does on commit: parse (noting the expression), then write.
    static func type(_ text: String, into d: LoftLineDocument, current: Double) throws -> Double {
        let style = ExpressionNumberStyle(variables: d.document.variableTable, units: d.units, recorder: d.expressionRecorder)
        let v = try style.parseStrategy.parse(text)
        return d.expressionRecorder.valueToWrite(v, current: current)
    }

    @Test func typedVariableStaysLinkedToTheMaterial() throws {
        let (d, id) = Self.setup()
        d.perform("Job") { $0.document.job.thickness = 0.5 }
        let v = try Self.type("=thickness - 0.1", into: d, current: Self.cutDepth(d, id))
        Self.setCutDepth(d, id, v)
        #expect(abs(Self.cutDepth(d, id) - 0.4) < 1e-12)
        #expect(d.document.linkedValues.count == 1)
        #expect(d.document.linkedValues[0].expression == "=thickness - 0.1")
        d.perform("Job") { $0.document.job.thickness = 1.0 }
        #expect(abs(Self.cutDepth(d, id) - 0.9) < 1e-12)
    }

    @Test func sameValueStillLinks() throws {
        let (d, id) = Self.setup()
        d.perform("Job") { $0.document.job.thickness = Self.cutDepth(d, id) }
        let cur = Self.cutDepth(d, id)
        let v = try Self.type("=thickness", into: d, current: cur)
        #expect(v == cur.nextUp)
        Self.setCutDepth(d, id, v)
        #expect(Self.cutDepth(d, id) == cur)   // exact value restored by the link
        #expect(d.document.linkedValues.count == 1)
    }

    @Test func plainNumberUnlinksAndNumbersDoNotLink() throws {
        let (d, id) = Self.setup()
        Self.setCutDepth(d, id, try Self.type("=thickness/2", into: d, current: Self.cutDepth(d, id)))
        #expect(d.document.linkedValues.count == 1)
        Self.setCutDepth(d, id, try Self.type("0.3", into: d, current: Self.cutDepth(d, id)))
        #expect(d.document.linkedValues.isEmpty)
        d.perform("Job") { $0.document.job.thickness = 2 }
        #expect(Self.cutDepth(d, id) == 0.3)
        // Unit-only expressions are not links.
        Self.setCutDepth(d, id, try Self.type("1/4in", into: d, current: 0.3))
        #expect(d.document.linkedValues.isEmpty)
    }

    @Test func userVariablesDriveJobAndToolpaths() throws {
        let (d, id) = Self.setup()
        d.perform("Vars") { $0.document.userVariables = [DocumentVariable(name: "board", value: 0.75)] }
        let t = try Self.type("=board", into: d, current: d.document.job.thickness)
        d.perform("Job") { $0.document.job.thickness = t }
        Self.setCutDepth(d, id, try Self.type("=thickness + 0.02", into: d, current: Self.cutDepth(d, id)))
        #expect(d.document.linkedValues.count == 2)
        d.perform("Vars") { $0.document.userVariables = [DocumentVariable(name: "board", value: 0.5)] }
        #expect(d.document.job.thickness == 0.5)
        #expect(abs(Self.cutDepth(d, id) - 0.52) < 1e-12)
        // Deleting the toolpath drops its link.
        d.deleteOperation(id)
        #expect(d.document.linkedValues.count == 1)
    }

    @Test func linksAreSavedWithTheFile() throws {
        var doc = Document()
        doc.linkedValues = [VariableLink(target: .job(sheetID: MaterialSheet.primaryID), path: ["thickness"], expression: "=a")]
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(Document.self, from: data)
        #expect(back.linkedValues == doc.linkedValues)
        #expect(VariableLink.usesVariables("=a*2", units: .inch))
        #expect(!VariableLink.usesVariables("1/4in + 2", units: .inch))
    }

    @Test func describeNamesTheParameter() throws {
        let (d, id) = Self.setup()
        Self.setCutDepth(d, id, try Self.type("=thickness", into: d, current: Self.cutDepth(d, id)))
        let label = VariableLinks.describe(d.document.linkedValues[0], in: d.project)
        #expect(label.hasSuffix("Depth › Cut depth"))
    }
}
