import CADCore
import Foundation
import Testing

@Suite struct LayoutPartLabelTests {
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [Vec2] {
        [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)]
    }

    @Test func labelGoesInTheMiddleOfARectangle() {
        let r = PartLabels.labelPoint(region: [rect(0, 0, 10, 4)])
        #expect(r != nil)
        #expect(abs((r?.clearance ?? 0) - 2) < 0.02)
        #expect(abs((r?.point.y ?? 0) - 2) < 0.02)
    }

    @Test func labelAvoidsHolesAndFeatures() {
        // 10x4 plate with a 4x4-ish hole on the left half: the label moves right.
        let r = PartLabels.labelPoint(region: [rect(0, 0, 10, 4), rect(0.5, 0.5, 4, 3)])
        #expect((r?.point.x ?? 0) > 4.5)
        // An engraved line across the middle splits the room.
        let l = PartLabels.labelPoint(region: [rect(0, 0, 10, 4)], obstacles: [[Vec2(0, 2), Vec2(10, 2)]])
        #expect((l?.clearance ?? 9) < 1.01)
    }

    @Test func emptyRegionHasNoLabel() {
        #expect(PartLabels.labelPoint(region: []) == nil)
    }
}
