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
