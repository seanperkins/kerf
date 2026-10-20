import Foundation
import Testing
@testable import CADCore

@Suite struct DrawingStartPointTests {
    @Test func rotatesClosedPathToNode() throws {
        let sq = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)
        let p = try #require(PathNodes.settingStart(sq, node: 2))
        #expect(p.start == Vec2(2, 2))
        #expect(p.segments.count == 4 && p.end == Vec2(2, 2))
        #expect(abs(p.signedArea() - sq.signedArea()) < 1e-12)
        #expect(PathNodes.anchors(p) == [Vec2(2, 2), Vec2(0, 2), Vec2(0, 0), Vec2(2, 0)])
        #expect(PathNodes.settingStart(Path(points: [.zero, Vec2(1, 0)], closed: false), node: 1) == nil)
        #expect(PathNodes.settingStart(sq, node: 9) == nil)
        let s = Shape(layerID: UUID(), paths: [sq])
        let moved = try #require(ShapeNodes.settingStart(s, NodeRef(shapeID: s.id, path: 0, node: 1)))
        #expect(moved.paths[0].start == Vec2(2, 0))
    }
}

@Suite struct DrawingSpanToArcTests {
    @Test func lineSpanBulgesIntoArc() throws {
        let sq = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], closed: true)
        let p = try #require(PathNodes.spanToArc(sq, segment: 0))
        #expect(p.segments.count >= 4 && p.start == Vec2(0, 0))
        // The bottom edge now bows a quarter of its length to its left (+Y, into the square).
        let b = Path(start: .zero, segments: Array(p.segments.prefix(p.segments.count - 3))).bounds(tolerance: 1e-5)
        #expect(abs(b.max.y - 0.5) < 1e-3)
        #expect(PathNodes.spanToArc(sq, segment: 9) == nil)
    }
}

@Suite struct DrawingArcTests {
    @Test func threePointArcPassesThroughAllPoints() throws {
        let p = try #require(ArcConstruction.threePoint(start: Vec2(1, 0), end: Vec2(-1, 0), through: Vec2(0, 1)))
        guard case .arc(let to, let c, let cw) = p.segments[0] else { Issue.record("not an arc"); return }
        #expect(c.isApproximatelyEqual(to: .zero, tolerance: 1e-12) && to == Vec2(-1, 0) && !cw)
        #expect(abs(p.bounds(tolerance: 1e-6).max.y - 1) < 1e-5)
        // Bulge below: clockwise.
        let q = try #require(ArcConstruction.threePoint(start: Vec2(1, 0), end: Vec2(-1, 0), through: Vec2(0, -1)))
        #expect(abs(q.bounds(tolerance: 1e-6).min.y + 1) < 1e-5)
        #expect(ArcConstruction.threePoint(start: .zero, end: Vec2(2, 0), through: Vec2(1, 0)) == nil)
    }

    @Test func majorArcThroughFarPoint() throws {
        // Through a point beyond the chord's far side: more than a half circle.
        let p = try #require(ArcConstruction.threePoint(start: Vec2(1, 0), end: Vec2(0, 1), through: Vec2(-1, 0)))
        #expect(abs(p.length(tolerance: 1e-6) - 1.5 * .pi) < 1e-4)
    }

    @Test func centreArcs() throws {
        let p = try #require(ArcConstruction.centerStartEnd(center: .zero, start: Vec2(2, 0), endDirection: Vec2(0, 5)))
        #expect(p.end.isApproximatelyEqual(to: Vec2(0, 2), tolerance: 1e-12))
        #expect(abs(p.length(tolerance: 1e-6) - .pi) < 1e-4)
        let full = try #require(ArcConstruction.centerAngles(center: .zero, radius: 1, startDegrees: 0, endDegrees: 360))
        #expect(full.isClosed && abs(full.length(tolerance: 1e-6) - 2 * .pi) < 1e-4)
        let cw = try #require(ArcConstruction.centerAngles(center: .zero, radius: 1, startDegrees: 90, endDegrees: 0))
        #expect(abs(cw.length(tolerance: 1e-6) - .pi / 2) < 1e-4)
    }
}
