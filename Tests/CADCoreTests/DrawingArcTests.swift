import Foundation
import Testing
@testable import CADCore

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
