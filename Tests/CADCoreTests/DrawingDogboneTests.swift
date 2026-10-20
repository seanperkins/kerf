import Foundation
import Testing
@testable import CADCore

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, ccw: Bool = true) -> Path {
    let p = Path(points: [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)], closed: true)
    return ccw ? p : p.reversed()
}

private func arcCount(_ p: Path) -> Int { p.segments.filter { if case .arc = $0 { return true }; return false }.count }

private func minDistance(_ p: Path, to q: Vec2) -> Double {
    p.flattened(tolerance: 1e-5).map { $0.distance(to: q) }.min() ?? .infinity
}

@Suite struct DrawingDogboneTests {
    let r = 0.125

    @Test func openingGetsReliefAtEveryCorner() {
        for ccw in [true, false] {
            let out = Dogbone.apply(to: [rect(0, 0, 2, 1, ccw: ccw)], radius: r, side: .opening)
            #expect(arcCount(out[0]) == 4)
            for c in [Vec2(0, 0), Vec2(2, 0), Vec2(2, 1), Vec2(0, 1)] { #expect(minDistance(out[0], to: c) < 3e-3) }
            // Over-cut is outside the opening, so the area grows.
            #expect(abs(out[0].signedArea(tolerance: 1e-5)) > 2)
            #expect(out[0].bounds(tolerance: 1e-5).min.x < 0)
        }
    }

    @Test func partWithoutInsideCornersIsUnchanged() {
        let sq = rect(0, 0, 2, 2)
        #expect(Dogbone.apply(to: [sq], radius: r, side: .part) == [sq])
    }

    @Test func partReliefsHolesAndNotches() {
        // L-shaped part: one concave corner at (1,1).
        let l = Path(points: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 1), Vec2(1, 1), Vec2(1, 2), Vec2(0, 2)], closed: true)
        let out = Dogbone.apply(to: [l, rect(0.25, 0.25, 0.5, 0.5)], radius: r, side: .part)
        #expect(arcCount(out[0]) == 1)
        #expect(minDistance(out[0], to: Vec2(1, 1)) < 3e-3)
        // The square hole (any winding) is relieved at all 4 corners.
        #expect(arcCount(out[1]) == 4)
        #expect(Dogbone.reliefCount([l, rect(0.25, 0.25, 0.5, 0.5, ccw: false)], radius: r, side: .part) == 5)
    }

    @Test func tBoneExtendsAlongLongEdge() {
        let out = Dogbone.apply(to: [rect(0, 0, 4, 1)], radius: r, style: .tBoneLong, side: .opening)
        #expect(arcCount(out[0]) == 4)
        let b = out[0].bounds(tolerance: 1e-5)
        // Long edges are horizontal: circles centred on them bulge past the long edges only.
        #expect(abs(b.min.y + r) < 1e-3 && abs(b.max.y - 1 - r) < 1e-3)
        #expect(abs(b.min.x) < 1e-6 && abs(b.max.x - 4) < 1e-6)
        let short = Dogbone.apply(to: [rect(0, 0, 4, 1)], radius: r, style: .tBoneShort, side: .opening)
        let bs = short[0].bounds(tolerance: 1e-5)
        #expect(abs(bs.min.x + r) < 1e-3 && abs(bs.min.y) < 1e-6)
    }

    @Test func obtuseCornersRespectMaxAngleAndShortEdgesAreSkipped() {
        let hex = ShapeFactory.polygon(center: .zero, radius: 1, sides: 6, rotation: 0)
        #expect(Dogbone.reliefCount([hex], radius: r, side: .opening, maxAngle: 100) == 0)
        #expect(Dogbone.reliefCount([hex], radius: r, side: .opening, maxAngle: 135) == 6)
        // Slot narrower than two relief trims: neighbouring reliefs would overlap, one is dropped.
        let tiny = rect(0, 0, 0.1, 3)
        let out = Dogbone.apply(to: [tiny], radius: r, side: .opening)
        #expect(arcCount(out[0]) < 4)
        #expect(out[0].isClosed)
    }

    @Test func curvesAndOpenPathsPassThrough() {
        let circle = ShapeFactory.circle(center: .zero, radius: 1)
        let open = Path(points: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: false)
        #expect(Dogbone.apply(to: [circle, open], radius: r, side: .opening) == [circle, open])
    }
}
