import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// Rail along y = 1 (x 1…9); section: flat for 0.5, then a 0.25 step down for the next 0.5.
private func moulding(tool: Tool = F.endMill, zZero: ZZeroMode = .materialTop,
                      roughing: Bool = false) throws -> (Toolpath, CAMContext) {
    let rail = Path(points: [Vec2(1, 1), Vec2(9, 1)], closed: false)
    let section = Path(points: [Vec2(20, 10), Vec2(20.5, 10), Vec2(20.5, 9.75), Vec2(21, 9.75)], closed: false)
    let (ctx, ids) = F.document([rail, section], zZero: zZero)
    let p = MouldingParameters(sectionShapeID: ids[1], side: .left, stepover: 0.05, roughing: roughing)
    let tps = try MouldingOperation(setup: OperationSetup(name: "M", toolID: tool.id, shapeIDs: ids), params: p)
        .generate(in: ctx)
    return (tps[0], ctx)
}

@Test func ops2DMouldingSectionProfileIsDepthBelowItsTop() throws {
    let shape = Shape(layerID: UUID(), paths: [Path(points: [Vec2(20, 10), Vec2(20.5, 10), Vec2(20.5, 9.75), Vec2(21, 9.75)],
                                                     closed: false)])
    let prof = try MouldingOperation.sectionProfile(shape, tolerance: 0.0005)
    #expect(abs(prof.width - 1) < 1e-12)
    #expect(prof.depth(at: 0.25) == 0)
    #expect(abs(prof.depth(at: 0.75) - 0.25) < 1e-9)
    #expect(abs(prof.depth(at: 5) - 0.25) < 1e-9) // flat beyond the end
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DMouldingCutsTheStepWithoutGouging(mode: ZZeroMode) throws {
    let (tp, ctx) = try moulding(zZero: mode)
    #expect(tp.kind == .moulding)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let cuts = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    #expect(!cuts.isEmpty)
    for p in cuts {
        let t = p.xy.y - 1          // offset to the left of the rail
        let d = ctx.coords.depth(ofMachineZ: p.z)
        #expect(t >= 0.5 + 0.125 - 0.02)  // a 1/4" end mill must stay r away from the step
        #expect(d <= 0.25 + 1e-9)
        #expect(p.xy.x >= 1 - 1e-6 && p.xy.x <= 9 + 1e-6)
    }
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.25)) < 1e-9)
}

@Test func ops2DMouldingRoughsInLevels() throws {
    let deep = Path(points: [Vec2(20, 10), Vec2(20.5, 10), Vec2(20.5, 9.5), Vec2(21, 9.5)], closed: false)
    let rail = Path(points: [Vec2(1, 1), Vec2(9, 1)], closed: false)
    let (ctx, ids) = F.document([rail, deep])
    let tp = try MouldingOperation(setup: OperationSetup(name: "M", toolID: F.endMill.id, shapeIDs: ids),
                                   params: MouldingParameters(sectionShapeID: ids[1], stepover: 0.1, roughing: true))
        .generate(in: ctx)[0]
    let levels = Set(tp.moves.compactMap { $0.target?.z }.filter { $0 < -1e-9 }.map { ($0 * 1000).rounded() })
    #expect(levels == [-125, -250, -375, -500])
    #expect(throws: CAMError.self) {
        try MouldingOperation(setup: OperationSetup(name: "M", toolID: F.endMill.id, shapeIDs: ids)).generate(in: ctx)
    }
}

/// A moulding pass is simplified for the toolpath: every point it drops must lie within the tolerance of the segment
/// that replaces it, however gently the pass curves. (The old loop compared each point with the segment from the
/// last kept point to the NEXT RAW point, so on a long shallow arc the error was not bounded: the V-carve simplifier
/// had the same loop and cut a hairline 0.012 in off its axis, issue #14.)
@Test func ops2DMouldingSimplifiedPassesStayWithinToleranceOfTheOriginal() {
    // A shallow arc: 200 points over 1.4 in, sagitta 0.03 in, sinking slowly.
    let radius = 8.0
    let arc = (0...200).map { i -> CutPoint in
        let a = Double(i) * 0.007 / radius
        return CutPoint(Vec2(radius * sin(a), radius * (1 - cos(a))), depth: 0.02 + 0.00002 * Double(i))
    }
    func p3(_ p: CutPoint) -> Vec3 { Vec3(p.xy, z: p.depth) }
    for tolerance in [0.0005, 0.002] {
        let kept = MouldingOperation.simplify(arc, tolerance: tolerance)
        #expect(kept.count > 2 && kept.count < arc.count)
        #expect(kept.first == arc.first && kept.last == arc.last)
        for p in arc.map(p3) {
            var best = Double.infinity
            for (a, b) in zip(kept.map(p3), kept.dropFirst().map(p3)) {
                let ab = b - a, ap = p - a
                let t = max(0, min(1, ap.dot(ab) / max(ab.dot(ab), 1e-300)))
                best = min(best, p.distance(to: a + ab * t))
            }
            #expect(best <= tolerance + 1e-12, Comment(rawValue: "tolerance \(tolerance): a point is \(best) from the simplified pass"))
        }
    }
}

/// A step in depth is a corner in 3D and must survive: dropping it would cut the step's wall as a slope.
@Test func ops2DMouldingSimplifyKeepsTheCornerOfAStep() {
    let pts = (0...20).map { i in CutPoint(Vec2(Double(i) * 0.1, 0), depth: i < 10 ? 0.1 : 0.35) }
    let kept = MouldingOperation.simplify(pts, tolerance: 0.001)
    #expect(kept.contains(pts[9]) && kept.contains(pts[10]))
    #expect(kept.first == pts.first && kept.last == pts.last)
}
