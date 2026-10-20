import Foundation
import Testing
@testable import CADCore

@Test func rectangleFlattensToFourPoints() {
    let p = ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 4, height: 2))
    #expect(p.flattened().count == 4)
    #expect(abs(p.signedArea() - 8) < 1e-12)
    #expect(p.bounds() == Rect2(x: 0, y: 0, width: 4, height: 2))
}

@Test func circleFlatteningRespectsTolerance() {
    let r = 2.0, tol = 0.001
    let pts = ShapeFactory.circle(center: Vec2(1, 1), radius: r).flattened(tolerance: tol)
    for (a, b) in zip(pts, pts.dropFirst() + [pts[0]]) {
        let mid = (a + b) * 0.5
        #expect(r - mid.distance(to: Vec2(1, 1)) <= tol + 1e-9)
    }
    #expect(abs(ShapeFactory.circle(center: .zero, radius: r).signedArea(tolerance: 1e-5) - .pi * r * r) < 1e-3)
}

@Test func reversedArcFlipsOrientation() {
    let c = ShapeFactory.circle(center: .zero, radius: 1)
    #expect(c.signedArea() > 0)
    #expect(c.reversed().signedArea() < 0)
}

@Test func mirrorTransformKeepsArcsAndFlipsDirection() {
    let c = ShapeFactory.circle(center: Vec2(2, 0), radius: 1)
    let m = c.transformed(.mirror(horizontalAxis: false, about: .zero))
    #expect(m.signedArea() < 0)
    #expect(abs(m.bounds().center.x + 2) < 1e-6)
}

@Test func transformInverseRoundTrips() throws {
    let t = Transform2D.rotation(0.7, about: Vec2(1, 2)).concatenating(.scale(2, 3)).concatenating(.translation(Vec2(5, -1)))
    let inv = try #require(t.inverted)
    let p = Vec2(3.5, -2.25)
    #expect(inv.apply(t.apply(p)).isApproximatelyEqual(to: p, tolerance: 1e-9))
}

@Test func kernelOffsetAndBooleanWork() {
    let sq = [[Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)]]
    let grown = GeomKernel.offset(sq, by: 1, join: .miter(limit: 2))
    #expect(grown.count == 1)
    #expect(abs(Rect2(points: grown[0]).width - 12) < 1e-6)
    let shrunk = PathOps.offset([ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 10, height: 10))], by: -1)
    #expect(abs(shrunk[0].bounds().width - 8) < 1e-6)
    let hole = GeomKernel.boolean(.difference, subject: sq, clip: [[Vec2(2, 2), Vec2(8, 2), Vec2(8, 8), Vec2(2, 8)]])
    #expect(hole.count == 2)
}

@Test func kernelVoronoiMedialAxisOfSquare() {
    let c = [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)]
    let segs = (0..<4).map { (c[$0], c[($0 + 1) % 4]) }
    let vd = GeomKernel.voronoi(segments: segs, scale: 1000, maxSampleStep: 0.5)
    #expect(vd.vertices.contains { $0.position.isApproximatelyEqual(to: Vec2(5, 5), tolerance: 1e-6) && abs($0.radius - 5) < 1e-6 })
    // Every sample on a primary finite edge is equidistant from its sites: radius <= 5.
    for e in vd.edges where e.isFinite && e.isPrimary {
        for s in vd.samples(of: e) { #expect(s.radius <= 5 + 1e-6) }
    }
}
