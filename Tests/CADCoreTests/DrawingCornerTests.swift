import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingCornerTests {
    let square = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)

    @Test func filletAllCornersOfSquare() {
        for p in [square, square.reversed()] {
            let f = CornerOps.apply(.fillet(radius: 0.5), to: p)
            #expect(f.segments.filter { if case .arc = $0 { return true }; return false }.count == 4)
            #expect(abs(abs(f.signedArea(tolerance: 1e-6)) - (4 - (4 - .pi) * 0.25)) < 1e-4)
            let b = f.bounds(tolerance: 1e-6)
            #expect(abs(b.width - 2) < 1e-5 && abs(b.height - 2) < 1e-5)
        }
    }

    @Test func chamferOneCorner() {
        let c = CornerOps.apply(.chamfer(distance: 0.5), to: square, corners: [2])
        #expect(abs(c.signedArea() - (4 - 0.125)) < 1e-9)
        #expect(c.segments.count == 5)
        #expect(!PathNodes.anchors(c).contains(Vec2(2, 2)))
    }

    @Test func oneSidedOpenOffset() throws {
        let l = Path(points: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4)], closed: false)  // left turn at (4,0)
        // Left = inside of the turn: mitred corner.
        let left = try #require(OpenOffset.oneSide(l, distance: 1, tolerance: 0.001))
        #expect(left.start.isApproximatelyEqual(to: Vec2(0, 1), tolerance: 1e-9))
        #expect(left.end.isApproximatelyEqual(to: Vec2(3, 4), tolerance: 1e-9))
        #expect(PathNodes.anchors(PathNodes.editable(left)).contains { $0.isApproximatelyEqual(to: Vec2(3, 1), tolerance: 1e-9) })
        // Right = outside: rounded corner, every point 1 away from the source.
        let right = try #require(OpenOffset.oneSide(l, distance: -1, tolerance: 0.001))
        #expect(right.start.isApproximatelyEqual(to: Vec2(0, -1), tolerance: 1e-9))
        #expect(right.end.isApproximatelyEqual(to: Vec2(5, 4), tolerance: 1e-9))
        for p in right.flattened(tolerance: 1e-4) {
            #expect(abs(VectorValidator.distance(p, toPolyline: l.flattened()) - 1) < 2e-3)
        }
        #expect(right.segments.contains { if case .arc = $0 { return true }; return false })
    }

    @Test func openPathInteriorCornerOnlyAndShortEdgesSkipped() {
        let l = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2)], closed: false)
        let f = CornerOps.apply(.fillet(radius: 0.5), to: l)
        #expect(f.start == Vec2(0, 0) && f.end == Vec2(2, 2))
        #expect(f.segments.count == 3)
        #expect(CornerOps.apply(.fillet(radius: 5), to: l) == l)
        // A circle (no line corners) is unchanged.
        let circle = ShapeFactory.circle(center: .zero, radius: 1)
        #expect(CornerOps.apply(.chamfer(distance: 0.1), to: circle) == circle)
    }
}
