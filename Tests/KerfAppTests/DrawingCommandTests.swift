import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct DrawingCommandTests {
    @Test func dogboneRelievesSelectedOpeningsInPlace() {
        var p = AppTestSupport.project()
        let ids = p.document.shapes.map(\.id)
        let n = VectorCommands.dogbone([ids[0]], toolDiameter: 0.25, style: .dogbone, side: .opening, maxAngle: 135, in: &p)
        #expect(n == 4)
        #expect(p.document.shapes[0].origin == .derived(operation: "dog-bone"))
        #expect(p.document.shapes[0].id == ids[0])
        #expect(p.document.shapes[1].paths == AppTestSupport.project().document.shapes[1].paths)
        // A plain rectangle cut as a part has no inside corners.
        var q = AppTestSupport.project()
        #expect(VectorCommands.dogbone(ids, toolDiameter: 0.25, style: .dogbone, side: .part, maxAngle: 135, in: &q) == 0)
    }
}
