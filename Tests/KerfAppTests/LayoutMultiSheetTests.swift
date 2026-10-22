import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

@Suite struct LayoutMultiSheetTests {
    /// 12x12 material and one 5x5 plate with a profile toolpath; nesting 9 copies needs 3 sheets.
    func overflowed() -> (KerfProject, NestingReport) {
        var doc = Document(job: JobSetup(width: 12, height: 12, thickness: 0.5))
        let plate = AppTestSupport.rect(20, 0, 5, 5, layer: doc.defaultLayerID)
        doc.add(plate)
        var p = KerfProject(document: doc)
        p.operations = [OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [plate.id])!]
        var o = NestingOptions.defaults(for: .inch)
        o.precision = .draft
        o.quantity = 9
        o.overflowSheets = true
        let r = NestingCommands.nest([plate.id], options: o, in: &p)
        return (p, r)
    }

    @Test func overflowCreatesParkedSheets() {
        let (p, r) = overflowed()
        #expect(r.placed == 9)
        #expect(r.unplaced == 0)
        #expect(r.sheets == 3)
        #expect(NestSheets.numbers(in: p.document) == [1, 2, 3])
        #expect(p.operations[0].setup.shapeIDs.count == 9)
        // Sheet 1 parts are on the material; the others are not, and are not validated as stray.
        let onMaterial = NestSheets.activeDocument(p.document).shapes
        #expect(onMaterial.count == 4)
        #expect(LayoutChecks.design(p.document, ignoredLayers: p.layoutIgnoredLayers).isEmpty)
    }

    @Test func onlyTheSheetOnTheMaterialIsMachined() {
        let (p, _) = overflowed()
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        let id = p.operations[0].id
        doc.calculateNow([id])
        let loops1 = doc.results[id]?.toolpaths.first?.xyBounds
        #expect(loops1 != nil)
        #expect((loops1?.max.x ?? 99) < 12.5)
        doc.showSheetOnMaterial(3)
        #expect(NestSheets.activeSheet(in: doc.document) == 3)
        #expect(doc.isStale(id))
        doc.calculateNow([id])
        #expect(doc.results[id]?.error == nil)
        #expect((doc.results[id]?.toolpaths.first?.xyBounds.max.x ?? 99) < 12.5)
    }

    @Test func toolpathsOnlyOnParkedSheetsExplainWhy() {
        var (p, _) = overflowed()
        let parked = NestSheets.shapes(onSheet: 2, in: p.document).map(\.id)
        let op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [parked[0]])!
        p.operations = [op]
        let r = ToolpathCalculator.calculate(op, project: p, library: .seeded, designRevision: 0, rapidRate: 100)
        #expect(r.error?.contains("not on the material") == true)
    }

    @Test func jobSheetHasOneSectionPerSheet() {
        let (p, _) = overflowed()
        let doc = KerfDocument(project: p, toolLibrary: AppTestSupport.library())
        let js = doc.makeJobSheet(settings: TimeEstimateSettings())
        #expect(js.sheets.count == 3)
        #expect(js.sheets[0].title.contains("on the material"))
        #expect(js.sheets.map(\.partNames.count).reduce(0, +) == 9)
        // Every sheet's shapes are drawn in the material frame.
        for s in js.sheets {
            for shape in s.shapes { #expect(shape.bounds().max.x <= 12 + 1e-6) }
        }
    }
}
