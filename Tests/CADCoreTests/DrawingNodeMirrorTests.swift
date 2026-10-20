import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingNodeMirrorTests {
    // A house: symmetric about x = 2 (nodes 0..4: bottom-left, bottom-right, right wall, roof peak, left wall).
    let house = Shape(layerID: UUID(), paths: [Path(points: [Vec2(0, 0), Vec2(4, 0), Vec2(4, 2), Vec2(2, 4), Vec2(0, 2)], closed: true)])

    func anchors(_ s: Shape) -> [Vec2] { PathNodes.anchors(ShapeNodes.editable(s).paths[0]) }

    @Test func leftRightMovesPartner() {
        let r = NodeRef(shapeID: house.id, path: 0, node: 2)
        let m = NodeMirror.moveNodes(house, [r], by: Vec2(1, 0.5), mode: .leftRight)
        let a = anchors(m)
        #expect(a[2] == Vec2(5, 2.5))
        #expect(a[4] == Vec2(-1, 2.5))
        #expect(a[0] == Vec2(0, 0))
    }

    @Test func nodeOnAxisOnlySlidesAlongIt() {
        let r = NodeRef(shapeID: house.id, path: 0, node: 3)
        let a = anchors(NodeMirror.moveNodes(house, [r], by: Vec2(1, 1), mode: .leftRight))
        #expect(a[3] == Vec2(2, 5))
    }

    @Test func offMatchesPlainMove() {
        let r = NodeRef(shapeID: house.id, path: 0, node: 2)
        let a = anchors(NodeMirror.moveNodes(house, [r], by: Vec2(1, 0), mode: .off))
        #expect(a[4] == Vec2(0, 2))
        #expect(a[2] == Vec2(5, 2))
    }

    @Test func bothMirrorsFourCorners() {
        let sq = Shape(layerID: UUID(), paths: [Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)])
        let r = NodeRef(shapeID: sq.id, path: 0, node: 2)
        let a = anchors(NodeMirror.moveNodes(sq, [r], by: Vec2(1, 1), mode: .both))
        #expect(a == [Vec2(-1, -1), Vec2(3, -1), Vec2(3, 3), Vec2(-1, 3)])
        #expect(NodeMirrorMode.off.next == .leftRight && NodeMirrorMode.both.next == .off)
    }

    @Test func handleMirrors() {
        // A symmetric arch: two cubics meeting at the top (x = 2).
        let p = Path(start: Vec2(0, 0), segments: [
            .cubic(to: Vec2(2, 3), control1: Vec2(0, 2), control2: Vec2(1, 3)),
            .cubic(to: Vec2(4, 0), control1: Vec2(3, 3), control2: Vec2(4, 2)),
        ])
        let s = Shape(layerID: UUID(), paths: [p])
        let r = NodeRef(shapeID: s.id, path: 0, node: 0)
        let m = NodeMirror.moveHandle(s, r, .outgoing, to: Vec2(-0.5, 2.5), keepSmooth: false, mode: .leftRight)
        let e = m.paths[0]
        #expect(PathNodes.handle(e, 0, .outgoing) == Vec2(-0.5, 2.5))
        #expect(PathNodes.handle(e, 2, .incoming) == Vec2(4.5, 2.5))
        // The top node's handles mirror each other too.
        let top = NodeRef(shapeID: s.id, path: 0, node: 1)
        let t = NodeMirror.moveHandle(s, top, .incoming, to: Vec2(0.5, 3.2), keepSmooth: false, mode: .leftRight).paths[0]
        #expect(PathNodes.handle(t, 1, .outgoing)!.isApproximatelyEqual(to: Vec2(3.5, 3.2), tolerance: 1e-9))
    }
}
