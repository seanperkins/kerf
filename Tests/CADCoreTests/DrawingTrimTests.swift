import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingTrimTests {
    let tol = 0.001
    let line = Path(points: [Vec2(0, 0), Vec2(10, 0)], closed: false)
    let cross1 = Path(points: [Vec2(3, -1), Vec2(3, 1)], closed: false)
    let cross2 = Path(points: [Vec2(7, -1), Vec2(7, 1)], closed: false)

    @Test func splitsSegmentsExactly() {
        let arc = PathSegment.arc(to: Vec2(-1, 0), center: .zero, clockwise: false)
        let s = PathSplitting.split(arc, from: Vec2(1, 0), at: 0.5)
        #expect(s.point.isApproximatelyEqual(to: Vec2(0, 1), tolerance: 1e-12))
        let cubic = PathSegment.cubic(to: Vec2(3, 0), control1: Vec2(1, 1), control2: Vec2(2, 1))
        let c = PathSplitting.split(cubic, from: .zero, at: 0.5)
        #expect(c.point.isApproximatelyEqual(to: Flattening.cubicPoint(.zero, Vec2(1, 1), Vec2(2, 1), Vec2(3, 0), 0.5), tolerance: 1e-12))
    }

    @Test func trimMiddleSpanOfLine() {
        let out = Trim.trimSpan(line, cutters: [cross1, cross2], at: Vec2(5, 0.1), tolerance: tol)
        #expect(out.count == 2)
        #expect(out[0].start == Vec2(0, 0) && out[0].end.isApproximatelyEqual(to: Vec2(3, 0), tolerance: 1e-9))
        #expect(out[1].start.isApproximatelyEqual(to: Vec2(7, 0), tolerance: 1e-9) && out[1].end == Vec2(10, 0))
    }

    @Test func trimEndSpanAndUncrossedPath() {
        let out = Trim.trimSpan(line, cutters: [cross1], at: Vec2(1, 0), tolerance: tol)
        #expect(out.count == 1 && out[0].start.isApproximatelyEqual(to: Vec2(3, 0), tolerance: 1e-9))
        #expect(Trim.trimSpan(line, cutters: [], at: Vec2(1, 0), tolerance: tol).isEmpty)
    }

    @Test func trimClosedCircleBetweenTwoCuts() {
        let circle = ShapeFactory.circle(center: .zero, radius: 2)
        let chord = Path(points: [Vec2(-3, 1), Vec2(3, 1)], closed: false)
        let out = Trim.trimSpan(circle, cutters: [chord], at: Vec2(0, 2), tolerance: tol)
        #expect(out.count == 1)
        #expect(!out[0].isClosed)
        let b = out[0].bounds(tolerance: 1e-5)
        // The cap above y=1 is gone; the rest keeps its arcs.
        // Crossings on curves are found on their flattening: accurate to the tolerance.
        #expect(abs(b.max.y - 1) < tol && abs(b.min.y + 2) < 1e-4)
        #expect(out[0].segments.allSatisfy { if case .arc = $0 { return true }; return false })
    }

    @Test func extendBothEndsToWalls() {
        let wallL = Path(points: [Vec2(0, -5), Vec2(0, 5)], closed: false)
        let wallR = Path(points: [Vec2(10, -5), Vec2(10, 5)], closed: false)
        let stub = Path(points: [Vec2(3, 0), Vec2(5, 0), Vec2(6, 0)], closed: false)
        let e = Extend.toBoundaries(stub, boundaries: [wallL, wallR], maxDistance: 100, tolerance: tol)
        #expect(e.start.isApproximatelyEqual(to: Vec2(0, 0), tolerance: 1e-9))
        #expect(e.end.isApproximatelyEqual(to: Vec2(10, 0), tolerance: 1e-9))
        #expect(e.segments.count == 2)
        // Nothing in the way: unchanged.
        #expect(Extend.toBoundaries(stub, boundaries: [], maxDistance: 100, tolerance: tol) == stub)
        // A curved end gains a straight extension.
        let hook = Path(start: Vec2(5, -2), segments: [.arc(to: Vec2(7, 0), center: Vec2(5, 0), clockwise: false)])
        let h = Extend.toBoundaries(hook, boundaries: [Path(points: [Vec2(0, 3), Vec2(10, 3)], closed: false)], maxDistance: 100, tolerance: tol)
        #expect(h.end.isApproximatelyEqual(to: Vec2(7, 3), tolerance: 1e-3) && h.segments.count == 2)
    }

    @Test func boundaryKeepsInsideOrOutside() {
        let box = Path(points: [Vec2(2, -2), Vec2(8, -2), Vec2(8, 2), Vec2(2, 2)], closed: true)
        let inside = Trim.toBoundary(line, boundary: [box], keepInside: true, tolerance: tol)
        #expect(inside.count == 1)
        #expect(inside[0].start.isApproximatelyEqual(to: Vec2(2, 0), tolerance: 1e-9) && inside[0].end.isApproximatelyEqual(to: Vec2(8, 0), tolerance: 1e-9))
        let outside = Trim.toBoundary(line, boundary: [box], keepInside: false, tolerance: tol)
        #expect(outside.count == 2)
        let away = Path(points: [Vec2(20, 0), Vec2(30, 0)], closed: false)
        #expect(Trim.toBoundary(away, boundary: [box], keepInside: true, tolerance: tol).isEmpty)
        #expect(Trim.toBoundary(away, boundary: [box], keepInside: false, tolerance: tol) == [away])
        // A closed circle crossing the box keeps its inside arc pieces.
        let circle = ShapeFactory.circle(center: Vec2(2, 0), radius: 1)
        let arcs = Trim.toBoundary(circle, boundary: [box], keepInside: true, tolerance: tol)
        #expect(arcs.count == 1)
        #expect(arcs[0].bounds(tolerance: 1e-5).min.x > 2 - 1e-6)
    }
}
