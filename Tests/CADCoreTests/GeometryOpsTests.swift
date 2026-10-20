import Foundation
import Testing
@testable import CADCore

@Suite struct GeometryJoinTests {
    @Test func joinsFourLinesIntoClosedSquareRegardlessOfDirection() {
        let lines = [
            Path(points: [Vec2(0, 0), Vec2(1, 0)], closed: false),
            Path(points: [Vec2(1, 1), Vec2(1, 0)], closed: false),       // reversed
            Path(points: [Vec2(0, 1), Vec2(0, 0.0004)], closed: false),  // gap within tolerance
            Path(points: [Vec2(1, 1), Vec2(0, 1)], closed: false),
        ]
        let joined = PathOps.joinOpenPaths(lines, tolerance: 0.001)
        #expect(joined.count == 1)
        #expect(joined[0].isClosed)
        #expect(approx(abs(joined[0].signedArea()), 1, 1e-3))
        #expect(joined[0].end == joined[0].start)
    }

    @Test func leavesDistantPathsApartAndClosedPathsUntouched() {
        let sq = ShapeFactory.rectangle(Rect2(x: 5, y: 5, width: 1, height: 1))
        let a = Path(points: [Vec2(0, 0), Vec2(1, 0)], closed: false)
        let b = Path(points: [Vec2(2, 0), Vec2(3, 0)], closed: false)
        let joined = PathOps.joinOpenPaths([a, sq, b], tolerance: 0.01)
        #expect(joined.count == 3)
        #expect(joined[0] == sq)
        #expect(joined.filter { !$0.isClosed }.count == 2)
    }

    @Test func prependsWhenMatchIsAtChainStart() {
        let a = Path(points: [Vec2(1, 0), Vec2(2, 0)], closed: false)
        let b = Path(points: [Vec2(0, 0), Vec2(1, 0)], closed: false)
        let joined = PathOps.joinOpenPaths([a, b], tolerance: 1e-6)
        #expect(joined.count == 1)
        #expect(joined[0].start == Vec2(0, 0) && joined[0].end == Vec2(2, 0))
    }

    @Test func joinsArcsWithLines() {
        let arc = Path(start: Vec2(1, 0), segments: [.arc(to: Vec2(-1, 0), center: .zero, clockwise: false)])
        let line = Path(points: [Vec2(-1, 0), Vec2(1, 0)], closed: false)
        let joined = PathOps.joinOpenPaths([arc, line], tolerance: 1e-6)
        #expect(joined.count == 1 && joined[0].isClosed)
        #expect(approx(joined[0].signedArea(tolerance: 1e-5), .pi / 2, 1e-3))
    }

    @Test func closeIfNearlyClosed() {
        let p = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0.0001, 0)], closed: false)
        let c = PathOps.closeIfNearlyClosed(p, tolerance: 0.001)
        #expect(c.isClosed && c.end == c.start)
        #expect(!PathOps.closeIfNearlyClosed(p, tolerance: 0.00001).isClosed)
    }
}

@Suite struct GeometryOrientationTests {
    @Test func normalizedOrientationMakesOuterCCWAndHolesCW() {
        let outer = ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 10, height: 10)).reversed()
        let hole = ShapeFactory.rectangle(Rect2(x: 2, y: 2, width: 2, height: 2))
        let island = ShapeFactory.rectangle(Rect2(x: 2.5, y: 2.5, width: 1, height: 1)).reversed()
        #expect(PathGeometry.nestingDepths([outer, hole, island]) == [0, 1, 2])
        let n = PathGeometry.normalizedOrientation([outer, hole, island])
        #expect(n[0].signedArea() > 0 && n[1].signedArea() < 0 && n[2].signedArea() > 0)
    }

    @Test func orientedIgnoresOpenPaths() {
        let open = Path(points: [Vec2(0, 0), Vec2(1, 0)], closed: false)
        #expect(PathGeometry.oriented(open, counterClockwise: false) == open)
    }

    @Test func flattenShapes() {
        let s = Shape(layerID: UUID(), paths: [ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 1, height: 1)),
                                                ShapeFactory.circle(center: .zero, radius: 1)])
        let f = PathGeometry.flatten([s], tolerance: 0.01)
        #expect(f.count == 2 && f[0].count == 4 && f[1].count > 8)
    }
}

@Suite struct GeometryTransformAlignTests {
    let layer = UUID()

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Shape {
        Shape(layerID: layer, paths: [ShapeFactory.rectangle(Rect2(x: x, y: y, width: w, height: h))])
    }

    @Test func moveScaleRotateMirror() {
        let s = [rect(0, 0, 2, 1)]
        #expect(approx(ShapeTransforms.move(s, by: Vec2(1, 2))[0].bounds(), Rect2(x: 1, y: 2, width: 2, height: 1)))
        #expect(approx(ShapeTransforms.scale(s, sx: 2, sy: 2)[0].bounds(), Rect2(x: -1, y: -0.5, width: 4, height: 2)))
        #expect(approx(ShapeTransforms.rotate(s, degrees: 90)[0].bounds(), Rect2(x: 0.5, y: -0.5, width: 1, height: 2)))
        let m = ShapeTransforms.mirror(s, axis: .vertical)[0]
        #expect(approx(m.bounds(), s[0].bounds()) && m.paths[0].signedArea() < 0)
        let r = ShapeTransforms.resize(s, width: 4, height: nil)[0].bounds()
        #expect(approx(r, Rect2(x: 0, y: 0, width: 4, height: 2)))
    }

    @Test func lockedShapesDoNotMove() {
        var s = rect(0, 0, 1, 1)
        s.isLocked = true
        #expect(ShapeTransforms.move([s], by: Vec2(5, 5))[0] == s)
    }

    @Test func alignEdgesAndCentres() {
        let s = [rect(0, 0, 1, 1), rect(3, 2, 2, 2)]
        let left = Alignment.align(s, .left)
        #expect(left.allSatisfy { approx($0.bounds().min.x, 0) })
        let top = Alignment.align(s, .top)
        #expect(top.allSatisfy { approx($0.bounds().max.y, 4) })
        let c = Alignment.align(s, .center, to: Rect2(x: 0, y: 0, width: 10, height: 10))
        #expect(c.allSatisfy { $0.bounds().center.isApproximatelyEqual(to: Vec2(5, 5), tolerance: 1e-9) })
        let g = Alignment.centerGroup(s, in: Rect2(x: 0, y: 0, width: 10, height: 10))
        #expect(PathGeometry.bounds(of: g).center.isApproximatelyEqual(to: Vec2(5, 5), tolerance: 1e-9))
    }

    @Test func distributeEqualGapsKeepsExtremesAndInputOrder() {
        let s = [rect(10, 0, 1, 1), rect(0, 0, 1, 1), rect(2, 0, 3, 1)]
        let d = Alignment.distributeSpacing(s, along: .horizontal)
        #expect(approx(d[1].bounds().min.x, 0) && approx(d[0].bounds().min.x, 10))
        // total 11, sizes 5, gap 3 → middle starts at 4
        #expect(approx(d[2].bounds().min.x, 4))
        let c = Alignment.distributeCenters(s, along: .horizontal)
        #expect(approx(c[2].bounds().center.x, 5.5))
    }
}

@Suite struct GeometryBooleanOffsetTests {
    let a = ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 2, height: 2))
    let b = ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 2, height: 2))

    @Test func booleansProduceExpectedAreas() {
        func area(_ p: [Path]) -> Double { p.reduce(0) { $0 + $1.signedArea() } }
        #expect(approx(area(PathOps.union([a], [b])), 7))
        #expect(approx(area(PathOps.union([a, b])), 7))
        #expect(approx(area(PathOps.subtract([a], minus: [b])), 3))
        #expect(approx(area(PathOps.intersect([a], with: [b])), 1))
        #expect(approx(abs(area(PathOps.xor([a], [b]))), 6))
    }

    @Test func sameDirectionHoleSurvivesOffsetAndBooleans() {
        // Two CCW circles: the inner one is a hole under the even-odd rule the CAM side uses.
        let ring = [ShapeFactory.circle(center: Vec2(10, 10), radius: 2),
                    ShapeFactory.circle(center: Vec2(10, 10), radius: 1)]
        let far = [ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 1, height: 1))]
        func area(_ p: [Path]) -> Double { p.reduce(0) { $0 + $1.signedArea(tolerance: 0.001) } }
        let ringArea = Double.pi * 3
        let grown = PathOps.offset(ring, by: 0.1, tolerance: 0.001)
        #expect(grown.count == 2)
        #expect(approx(area(grown), Double.pi * (2.1 * 2.1 - 0.9 * 0.9), 0.02))
        let welded = PathOps.union(shapes: [ring, far], tolerance: 0.001)
        #expect(welded.count == 3)
        #expect(approx(area(welded), ringArea + 1, 0.02))
        #expect(approx(area(PathOps.subtract(far + [ShapeFactory.rectangle(Rect2(x: 5, y: 5, width: 10, height: 10))],
                                              minus: ring, tolerance: 0.001)), 1 + 100 - ringArea, 0.02))
        #expect(approx(area(PathOps.intersect(ring, with: [ShapeFactory.rectangle(Rect2(x: 5, y: 5, width: 10, height: 10))],
                                              tolerance: 0.001)), ringArea, 0.02))
    }

    @Test func offsetOpenMakesSleeve() {
        let line = Path(points: [Vec2(0, 0), Vec2(10, 0)], closed: false)
        let s = PathOps.offsetOpen([line], by: 1, end: .openButt)
        #expect(s.count == 1)
        #expect(approx(s[0].bounds(), Rect2(x: 0, y: -1, width: 10, height: 2)))
    }
}
