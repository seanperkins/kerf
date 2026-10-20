import CADCore
import Foundation
import Testing

@Suite struct LayoutFixturesTests {
    @Test func clampsSitOnTheEdgesSpreadEvenly() {
        let job = JobSetup(width: 48, height: 24)
        let r = Fixtures.clampRects(job: job, length: 3, reach: 0.75, outside: 1.5, perSideEdges: 2, perEndEdges: 1,
                                    endInset: 2)
        #expect(r.count == 6)
        // Left edge clamps straddle x = 0.
        let left = r.filter { $0.min.x < 0 && $0.max.x < 1 }
        #expect(left.count == 2)
        #expect(left.allSatisfy { abs($0.min.x + 1.5) < 1e-9 && abs($0.max.x - 0.75) < 1e-9 })
        #expect(abs(left.map(\.min.y).min()! - 2) < 1e-9)
        #expect(abs(left.map(\.max.y).max()! - 22) < 1e-9)
        // One clamp centred on the bottom and on the top edge.
        #expect(r.contains { abs($0.center.x - 24) < 1e-9 && $0.min.y < 0 })
        #expect(r.contains { abs($0.center.x - 24) < 1e-9 && $0.max.y > 24 })
    }

    @Test func holeGridIsCentredInsideTheInset() {
        let pts = Fixtures.holeGrid(in: Rect2(x: 0, y: 0, width: 24, height: 12), spacing: Vec2(10, 10), inset: 1)
        #expect(pts.count == 3 * 2)
        #expect(abs(pts[0].x - 2) < 1e-9)  // 22 wide, 2 gaps of 10: 1 in left over each side
        #expect(abs(pts[0].y - 1) < 1e-9)
        #expect(abs(pts[1].x - 12) < 1e-9)
    }

    @Test func keepOutShapesAreZonesAndNeverMachinedOrMoved() {
        var d = Document(job: JobSetup(width: 20, height: 10))
        let clamps = Layer(name: "Clamps", keepOut: KeepOutZone(height: 1))
        d.layers.append(clamps)
        let c = Shape(name: "C", layerID: clamps.id, paths: [ShapeFactory.rectangle(Rect2(x: -1, y: 4, width: 2, height: 2))])
        let part = Shape(name: "P", layerID: d.defaultLayerID, paths: [ShapeFactory.rectangle(Rect2(x: 5, y: 1, width: 2, height: 2))])
        d.add(c); d.add(part)
        let zones = Fixtures.zones(in: d)
        #expect(zones.count == 1)
        #expect(zones[0].height == 1)
        #expect(NestSheets.activeDocument(d).shape(id: c.id) == nil)
        #expect(NestSheets.activeDocument(d).shape(id: part.id) != nil)
        // Showing another sheet moves parts, never clamps.
        NestSheets.ensureLayer(forSheet: 2, in: &d)
        NestSheets.activate(2, in: &d)
        #expect(d.shape(id: c.id)!.bounds() == c.bounds())
        #expect(d.shape(id: part.id)!.bounds().min.x > 20)
    }
}
