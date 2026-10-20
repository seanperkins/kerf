import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct LayoutNestingCommandTests {
    /// 30x20 material; three 8x6 plates (one with a hole) stacked off the material.
    static func project() -> (KerfProject, [UUID]) {
        var doc = Document(job: JobSetup(width: 30, height: 20, thickness: 0.75))
        let layer = doc.defaultLayerID
        var ids: [UUID] = []
        for i in 0..<3 {
            let s = AppTestSupport.rect(40, Double(i) * 7, 8, 6, layer: layer)
            doc.add(s)
            ids.append(s.id)
        }
        let hole = Shape(name: "hole", layerID: layer, paths: [ShapeFactory.circle(center: Vec2(44, 3), radius: 1)])
        doc.add(hole)
        ids.append(hole.id)
        return (KerfProject(document: doc), ids)
    }

    static var fastOptions: NestingOptions {
        var o = NestingOptions.defaults(for: .inch)
        o.precision = .draft
        return o
    }

    @Test func movesPartsOntoTheMaterialWithTheirFeatures() {
        var (p, ids) = Self.project()
        let report = NestingCommands.nest(ids, options: Self.fastOptions, in: &p)
        #expect(report.placed == 3)
        #expect(report.unplaced == 0)
        let material = p.document.job.materialBounds.insetBy(0.25 - 1e-6)
        for s in p.document.shapes {
            let b = s.bounds()
            #expect(material.contains(b.min) && material.contains(b.max))
        }
        // The hole moved with its plate (same offset, or rotated with it).
        let plate = p.document.shapes[0].bounds(), hole = p.document.shapes[3].bounds()
        #expect(plate.contains(hole.min) && plate.contains(hole.max))
    }

    @Test func copiesAreAddedToToolpathsOfTheOriginal() {
        var (p, ids) = Self.project()
        let op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [ids[0]])!
        p.operations = [op]
        var o = Self.fastOptions
        o.quantity = 2
        let report = NestingCommands.nest([ids[0]], options: o, in: &p)
        #expect(report.placed == 2)
        #expect(p.document.shapes.count == 5)
        #expect(p.operations[0].setup.shapeIDs.count == 2)
    }

    @Test func avoidsVectorsThatAreNotNested() {
        var (p, ids) = Self.project()
        // A fixed obstacle covering the left half of the material.
        let block = AppTestSupport.rect(0, 0, 15, 20, layer: p.document.defaultLayerID)
        p.document.add(block)
        _ = NestingCommands.nest([ids[0]], options: Self.fastOptions, in: &p)
        #expect(p.document.shapes[0].bounds().min.x >= 15 + 0.375 - 1e-6)
    }

    @Test func reportsPartsThatDoNotFit() {
        var (p, ids) = Self.project()
        var o = Self.fastOptions
        o.quantity = 10
        let report = NestingCommands.nest([ids[0]], options: o, in: &p)
        #expect(report.placed < 10)
        #expect(report.unplaced == 10 - report.placed)
        #expect(report.summary.contains("did not fit"))
    }
}
