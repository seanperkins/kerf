import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingGuideTests {
    @Test func snapsAxesToGuidesAndNodes() {
        let guides = [GuideLine(isVertical: true, position: 3)]
        let r = AxisSnap.snap(Vec2(3.05, 7.33), guides: guides, alignWith: [Vec2(10, 7.3)], tolerance: 0.1, grid: 0.25)
        #expect(r.point == Vec2(3, 7.3))
        #expect(r.x == 3 && r.xSource == nil && r.ySource == Vec2(10, 7.3))
        // Nothing near: grid only, not snapped.
        let g = AxisSnap.snap(Vec2(5.1, 5.1), guides: guides, alignWith: [], tolerance: 0.1, grid: 0.25)
        #expect(!g.snapped && g.point == Vec2(5, 5))
    }

    @Test func guidesSurviveCodingAndOldFilesDecode() throws {
        var d = Document()
        d.guides = [GuideLine(isVertical: false, position: 2)]
        let json = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Document.self, from: json)
        #expect(back.guides == d.guides)
        // A file written before guides existed has no "guides" key at all.
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object.removeValue(forKey: "guides") != nil)
        let old = try JSONDecoder().decode(Document.self, from: try JSONSerialization.data(withJSONObject: object))
        #expect(old.guides == nil)
    }
}
