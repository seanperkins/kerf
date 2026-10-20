import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingBoundaryTests {
    let a = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)], closed: true)
    let b = Path(points: [Vec2(1.2, 0), Vec2(2.2, 0), Vec2(2.2, 3), Vec2(1.2, 3)], closed: true)

    @Test func rectangleWithMargin() {
        let r = BoundaryVector.make(.rectangle, around: [a, b], margin: 0.5, gap: 0, tolerance: 0.001)
        #expect(r.count == 1)
        let box = r[0].bounds()
        #expect(box.min == Vec2(-0.5, -0.5) && box.max == Vec2(2.7, 3.5))
    }

    @Test func convexHullArea() {
        let hull = BoundaryVector.convexHull([Vec2(0, 0), Vec2(2, 0), Vec2(1, 1), Vec2(2, 2), Vec2(0, 2)])
        #expect(hull.count == 4)
        #expect(abs(PathGeometry.area(hull) - 4) < 1e-12)
        let h = BoundaryVector.make(.convexHull, around: [a, b], margin: 0, gap: 0, tolerance: 0.001)
        // Hull of the two boxes: covers both plus the wedge between.
        #expect(abs(h[0].signedArea()) > 1 + 3 && abs(h[0].signedArea()) < 2.2 * 3)
    }

    @Test func shrinkWrapBridgesSmallGapsOnly() {
        let wrapped = BoundaryVector.make(.shrinkWrap, around: [a, b], margin: 0, gap: 0.15, tolerance: 0.001)
        #expect(wrapped.count == 1)  // the 0.2 gap is bridged
        let area = abs(wrapped[0].signedArea())
        #expect(area > 4 && area < 4.6)  // the two areas plus the bridge, far less than the hull
        let apart = BoundaryVector.make(.shrinkWrap, around: [a, b], margin: 0, gap: 0.05, tolerance: 0.001)
        #expect(apart.count == 2)
    }
}
