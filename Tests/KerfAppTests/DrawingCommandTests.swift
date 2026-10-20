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

    @Test func textStaysEditableUntilNodeEdit() throws {
        var p = AppTestSupport.project()
        let spec = TextSpec(string: "HI", fontName: "Helvetica", size: 1, alignment: .center, anchor: Vec2(10, 5))
        let s = try TextOutliner().shape(for: spec, layerID: p.document.defaultLayerID)
        p.document.add(s)
        p.transformShapes([s.id], by: .translation(Vec2(1, 0)))
        var edited = p.document.shape(id: s.id)!.text!
        edited.string = "HELLO"
        try VectorCommands.updateText(s.id, spec: edited, in: &p)
        let after = p.document.shape(id: s.id)!
        #expect(after.text?.string == "HELLO")
        #expect(after.name == "HELLO")
        // Centre-justified: still centred on the moved anchor.
        #expect(abs(after.bounds().center.x - 11) < 0.1)
        p.moveNodes([NodeRef(shapeID: s.id, path: 0, node: 0)], by: Vec2(0.01, 0))
        #expect(p.document.shape(id: s.id)!.text == nil)
    }

    @Test func repairDeletesDuplicatesAndPrunesOperations() {
        var p = AppTestSupport.project()
        let orig = p.document.shapes[0]
        var dup = orig
        dup.id = UUID()
        p.document.add(dup)
        let issues = VectorValidator.check(VectorCommands.validationScope([], in: p), tolerance: 0.0005)
        #expect(issues.map(\.kind) == [.duplicate])
        #expect(VectorCommands.repair(issues, in: &p) == 1)
        #expect(p.document.shapes.count == 2)
    }

    @Test func mirrorAboutMaterialCentreAndCopy() {
        var p = AppTestSupport.project()
        p.document.job.width = 10
        let first = p.document.shapes[0]  // x 1...3
        VectorCommands.mirror([first.id], horizontally: true, pivot: .materialCenter, keepOriginal: false, in: &p)
        let b = p.document.shape(id: first.id)!.bounds()
        #expect(abs(b.min.x - 7) < 1e-9 && abs(b.max.x - 9) < 1e-9)
        let copies = VectorCommands.mirror([first.id], horizontally: false, pivot: .maxEdge, keepOriginal: true, in: &p)!
        #expect(copies.count == 1 && p.document.shapes.count == 3)
        let c = p.document.shape(id: copies[0])!.bounds()
        #expect(abs(c.min.y - 2) < 1e-9 && abs(c.max.y - 3) < 1e-9)
    }

    @Test func trimClickAndTrimToBoundary() {
        var p = AppTestSupport.project()  // rectangles x 1...3 and 5...7, y 1...2
        let line = Shape(layerID: p.document.defaultLayerID, paths: [Path(points: [Vec2(0, 1.5), Vec2(8, 1.5)], closed: false)])
        p.document.add(line)
        #expect(VectorCommands.trim(at: Vec2(4, 1.5), pickTolerance: 0.05, in: &p))
        #expect(p.document.shape(id: line.id)!.paths.count == 2)
        #expect(!VectorCommands.trim(at: Vec2(40, 40), pickTolerance: 0.05, in: &p))
        // Trim the remaining line pieces to the first rectangle: only the part inside it stays.
        let rect = p.document.shapes[0].id
        #expect(VectorCommands.trimToBoundary([rect, line.id], keepInside: true, in: &p) == 1)
        let left = p.document.shape(id: line.id)!
        #expect(left.paths.count == 1)
        #expect(abs(left.bounds().min.x - 1) < 1e-6 && abs(left.bounds().max.x - 3) < 1e-6)
    }

    @Test func filletSelectedNodeOrAllCorners() {
        var p = AppTestSupport.project()
        let a = p.document.shapes[0].id, b = p.document.shapes[1].id
        VectorCommands.treatCorners(.chamfer(distance: 0.25), shapes: [], nodes: [NodeRef(shapeID: a, path: 0, node: 0)], in: &p)
        #expect(p.document.shape(id: a)!.paths[0].segments.count == 5)
        #expect(VectorCommands.treatCorners(.fillet(radius: 0.25), shapes: [b], nodes: [], in: &p) == 1)
        #expect(p.document.shape(id: b)!.paths[0].segments.filter { if case .arc = $0 { return true }; return false }.count == 4)
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
