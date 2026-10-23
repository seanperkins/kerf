import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// `Polygon2D.parts(of:offsets:join:tolerance:)` groups the loops a profile offsets together (issue #53).
@Suite struct Polygon2DPartsTests {
    func parts(_ loops: [Path], offset: Double = 0) -> [Int] {
        let flat = loops.map { $0.flattened() }
        return Polygon2D.parts(of: flat, offsets: flat.map { _ in offset }, join: .round, tolerance: 0.001)
    }

    @Test func loopsThatNestOrOverlapAreOnePart() {
        let p = parts([F.rect(0, 0, 6, 4), F.rect(2, 1, 2, 2), F.rect(5, 3, 3, 3), F.rect(20, 0, 1, 1)])
        #expect(p[0] == p[1] && p[0] == p[2])     // a hole, and a rectangle overlapping the outline
        #expect(p[3] != p[0])
    }

    @Test func loopsThatOnlyTouchOrStayApartAreNotUntilTheirOffsetsMeet() {
        let touching = [F.rect(0, 0, 2, 2), F.rect(2, 0, 2, 2)]
        let apart = [F.rect(0, 0, 2, 2), F.rect(2.3, 0, 2, 2)]
        #expect(parts(touching)[0] != parts(touching)[1])
        #expect(parts(apart)[0] != parts(apart)[1])
        #expect(parts(apart, offset: 0.1)[0] != parts(apart, offset: 0.1)[1])
        #expect(parts(apart, offset: 0.2)[0] == parts(apart, offset: 0.2)[1])    // grown 0.2 each, 0.3 apart
        #expect(parts(apart, offset: -0.2)[0] != parts(apart, offset: -0.2)[1])  // shrunk, they move apart
    }

    @Test func aChainOfLoopsIsOnePartWhateverItsOrder() {
        let chain = [F.rect(0, 0, 1, 1), F.rect(2.2, 0, 1, 1), F.rect(1.1, 0, 1, 1)]   // the third bridges the others
        let p = parts(chain, offset: 0.06)
        #expect(Set(p).count == 1)
        #expect(Set(parts(chain.reversed(), offset: 0.06)).count == 1)
    }

    /// A hole always overlaps the loop it is in as drawn, so growing it or shrinking it never changes which loops
    /// are one part: the profile groups every vector with the same offset.
    @Test func aHolesOffsetDirectionNeverChangesTheGrouping() {
        var rng = SplitMix64(seed: 99)
        func u(_ a: Double, _ b: Double) -> Double { a + (b - a) * rng.next() }
        for _ in 0..<80 {
            var loops: [[Vec2]] = [F.rect(0, 0, 6, 6).flattened()]
            for _ in 0..<Int(u(1, 5)) {
                let w = u(0.3, 1.2), h = u(0.3, 1.2), x = u(0.1, 5.8 - w), y = u(0.1, 5.8 - h)
                loops.append(F.rect(x, y, w, h).flattened())
                if rng.next() < 0.4 { loops.append(F.rect(x + 0.1, y + 0.1, max(w - 0.2, 0.05), max(h - 0.2, 0.05)).flattened()) }
            }
            if rng.next() < 0.5 { loops.append(F.rect(6 + u(0.05, 0.6), u(0, 5), u(0.2, 1), u(0.2, 1)).flattened()) }
            let holes = Polygon2D.holes(in: loops, tolerance: 0.001)
            for grow in [0.125, 0.225, 0.4, -0.125, -0.225, -0.4] {
                let signed = Polygon2D.parts(of: loops, offsets: holes.map { $0 ? -grow : grow }, join: .round, tolerance: 0.001)
                let uniform = Polygon2D.parts(of: loops, offsets: loops.map { _ in grow }, join: .round, tolerance: 0.001)
                #expect(signed == uniform, "grow \(grow)")
            }
        }
    }
}
