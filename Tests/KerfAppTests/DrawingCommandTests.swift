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

    @Test func rectangularArrayCopiesWithGap() {
        var p = AppTestSupport.project()
        let first = p.document.shapes[0]
        let ids = VectorCommands.rectangularArray([first.id], rows: 2, columns: 2, x: 0.5, y: 1, spacing: .gap, in: &p)
        #expect(ids.count == 3)
        #expect(p.document.shapes.count == 5)
        let b = p.bounds(of: Set(ids + [first.id]))
        // 2x1 rectangle at (1,1): two columns with a 0.5 gap, two rows with a 1 gap.
        #expect(b.min == Vec2(1, 1) && b.max == Vec2(5.5, 4))
    }

    @Test func arrayCopiesKeepGroupsSeparate() {
        var p = AppTestSupport.project()
        let ids = p.document.shapes.map(\.id)
        p.document.group(ids)
        let new = VectorCommands.arrayCopies([ids[0]], transforms: [.translation(Vec2(0, 5)), .translation(Vec2(0, 10))], in: &p)
        #expect(new.count == 4)  // the whole group is copied twice
        let groups = Set(p.document.shapes(ids: new).compactMap(\.groupID))
        #expect(groups.count == 2 && !groups.contains(p.document.shapes[0].groupID!))
    }
}
