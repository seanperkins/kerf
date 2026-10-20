import CADCore
import Foundation
import Testing

@Suite struct LayoutNestSheetsTests {
    /// 20x10 material, one part on sheet 1 and one on a parked sheet 2.
    func doc() -> (Document, UUID, UUID) {
        var d = Document(job: JobSetup(width: 20, height: 10))
        let base = Shape(name: "a", layerID: d.defaultLayerID, paths: [ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 2, height: 2))])
        d.add(base)
        let layer = NestSheets.ensureLayer(forSheet: 2, in: &d)
        let off = NestSheets.offset(ofSheet: 2, in: d)
        let parked = Shape(name: "b", layerID: layer,
                           paths: [ShapeFactory.rectangle(Rect2(x: 5 + off.x, y: 1 + off.y, width: 2, height: 2))])
        d.add(parked)
        return (d, base.id, parked.id)
    }

    @Test func extraSheetsParkBesideTheMaterial() {
        let (d, _, _) = doc()
        #expect(NestSheets.numbers(in: d) == [1, 2])
        #expect(NestSheets.activeSheet(in: d) == 1)
        let off = NestSheets.offset(ofSheet: 2, in: d)
        #expect(off.x >= 20)
        #expect(off.y == 0)
        #expect(NestSheets.offset(ofSheet: 1, in: d) == .zero)
    }

    @Test func camSeesOnlyTheSheetOnTheMaterial() {
        let (d, a, b) = doc()
        let active = NestSheets.activeDocument(d)
        #expect(active.shape(id: a) != nil)
        #expect(active.shape(id: b) == nil)
        // Shapes of each sheet come back in the material frame.
        let s2 = NestSheets.shapes(onSheet: 2, in: d)
        #expect(abs(s2[0].bounds().min.x - 5) < 1e-9)
    }

    @Test func activatingASheetSwapsPositions() {
        var (d, a, b) = doc()
        NestSheets.activate(2, in: &d)
        #expect(NestSheets.activeSheet(in: d) == 2)
        #expect(abs(d.shape(id: b)!.bounds().min.x - 5) < 1e-9)
        #expect(d.shape(id: a)!.bounds().min.x > 20)
        let active = NestSheets.activeDocument(d)
        #expect(active.shape(id: a) == nil && active.shape(id: b) != nil)
        NestSheets.activate(1, in: &d)
        #expect(abs(d.shape(id: a)!.bounds().min.x - 1) < 1e-9)
        #expect(NestSheets.activeSheet(in: d) == 1)
    }

    @Test func oldLayersDecodeWithoutASheet() throws {
        let json = ##"{"id":"00000000-0000-4000-8000-000000000001","name":"L","isVisible":true,"isLocked":false,"colorHex":"#000000"}"##
        let l = try JSONDecoder().decode(Layer.self, from: Data(json.utf8))
        #expect(l.sheet == nil)
    }
}
