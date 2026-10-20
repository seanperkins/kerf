import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func drill(_ paths: [Path], zZero: ZZeroMode = .materialTop, params: DrillParameters) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document(paths, zZero: zZero)
    let op = DrillOperation(setup: OperationSetup(name: "Drill", toolID: F.drill.id, shapeIDs: ids), params: params)
    let tps = try op.generate(in: ctx)
    #expect(tps.count == 1)
    return (tps[0], ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DDrillPecksToDepthAtCircleCentres(mode: ZZeroMode) throws {
    let circles = [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.125),
                   ShapeFactory.circle(center: Vec2(5, 1), radius: 0.2),
                   ShapeFactory.circle(center: Vec2(1.5, 1), radius: 0.1)]
    let (tp, ctx) = try drill(circles, zZero: mode, params: DrillParameters(cutDepth: 0.5, peckDepth: 0.2, retractHeight: 0.05))
    let c = ctx.coords
    #expect(F.conventionViolations(tp, coords: c).isEmpty)
    #expect(abs(tp.minZ! - c.z(depth: 0.5)) < 1e-9)
    #expect(abs(tp.minZ! - (mode == .materialTop ? -0.5 : 0.25)) < 1e-9)
    // Feeds only straight down at hole centres, at the plunge rate.
    let centres = [Vec2(1, 1), Vec2(5, 1), Vec2(1.5, 1)]
    var cur: Vec3?
    var feedsPerHole: [Int] = [0, 0, 0]
    for m in tp.moves {
        if case .linear(let p, let f) = m {
            #expect(f == F.drill.plungeRate)
            #expect(cur.map { $0.xy.distance(to: p.xy) < 1e-12 && p.z < $0.z } ?? false)
            if let i = centres.firstIndex(where: { $0.distance(to: p.xy) < 1e-9 }) { feedsPerHole[i] += 1 }
        }
        cur = m.target ?? cur
    }
    // 0.5 deep at 0.2 pecks: 0.2, 0.4, 0.5.
    #expect(feedsPerHole == [3, 3, 3])
    // Nearest-neighbour order from the origin: (1,1) → (1.5,1) → (5,1).
    let holeOrder = tp.moves.compactMap { m -> Vec2? in
        if case .linear(let p, _) = m { return p.xy } else { return nil }
    }.reduce(into: [Vec2]()) { acc, p in if acc.last != p { acc.append(p) } }
    #expect(holeOrder == [Vec2(1, 1), Vec2(1.5, 1), Vec2(5, 1)])
}

@Test func ops2DDrillRetractsBetweenPecksAndDwells() throws {
    let (tp, ctx) = try drill([ShapeFactory.circle(center: Vec2(2, 2), radius: 0.25)],
                              params: DrillParameters(cutDepth: 0.3, peckDepth: 0.1, retractHeight: 0.05, dwellSeconds: 0.5))
    let c = ctx.coords
    let retractZ = c.z(aboveTop: 0.05)
    let retracts = tp.moves.filter { if case .rapid(let p) = $0 { return abs(p.z - retractZ) < 1e-9 } else { return false } }
    #expect(retracts.count == 3) // initial descent to the retract plane + 2 between pecks
    #expect(tp.moves.contains(.dwell(seconds: 0.5)))
    // Rapids into the hole never go below the previous peck.
    var deepest = c.materialTopZ
    for m in tp.moves {
        if case .rapid(let p) = m { #expect(p.z >= deepest - 1e-9) }
        if case .linear(let p, _) = m { deepest = min(deepest, p.z) }
    }
}

@Test func ops2DDrillSinglePlungeAndPointsAndDedup() throws {
    let point = Path(start: Vec2(3, 3), segments: [], isClosed: false)
    let ring = [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.5), ShapeFactory.circle(center: Vec2(1, 1), radius: 0.25)]
    let line = Path(points: [Vec2(0, 0), Vec2(2, 0)], closed: false)
    let (tp, _) = try drill([point, line] + ring, params: DrillParameters(cutDepth: 0.25, peckDepth: 0))
    #expect(tp.metadata["holes"] == "2")
    #expect(tp.moves.filter { if case .linear = $0 { return true } else { return false } }.count == 2)
}

@Test func ops2DDrillRejectsBadInput() {
    let (ctx, ids) = F.document([ShapeFactory.circle(center: Vec2(1, 1), radius: 0.1)])
    let op = DrillOperation(setup: OperationSetup(name: "D", toolID: F.drill.id, shapeIDs: ids),
                            params: DrillParameters(startDepth: 0.5, cutDepth: 0.25))
    #expect(throws: CAMError.self) { try op.generate(in: ctx) }
}
