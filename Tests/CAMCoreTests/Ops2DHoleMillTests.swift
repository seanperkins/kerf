import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func holeMill(_ params: HoleMillParameters, paths: [Path] = [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5)],
                      zZero: ZZeroMode = .materialTop) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document(paths, zZero: zZero)
    let tps = try HoleMillOperation(setup: OperationSetup(name: "H", toolID: F.endMill.id, shapeIDs: ids), params: params)
        .generate(in: ctx)
    #expect(tps.count == 1)
    return (tps[0], ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DHoleMillHelicalBoreStaysOnTheHoleRadius(mode: ZZeroMode) throws {
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.3), zZero: mode)
    #expect(tp.kind == .holeMill)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.3)) < 1e-9)
    let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    // The tool centre runs at hole radius − tool radius (0.375), or returns to the centre.
    for q in cut {
        let r = q.xy.distance(to: Vec2(3, 3))
        #expect(abs(r - 0.375) < 0.001 || r < 1e-9)
    }
    // Depth never increases by more than the stepdown (0.125) per turn: monotone descent.
    var prev = 0.0
    for q in cut {
        let d = ctx.coords.depth(ofMachineZ: q.z)
        #expect(d >= prev - 1e-9)
        prev = d
    }
    // Helix is counter-clockwise for climb.
    let ring = cut.filter { abs($0.xy.distance(to: Vec2(3, 3)) - 0.375) < 0.001 }.prefix(40).map(\.xy)
    let a0 = (ring[0] - Vec2(3, 3)).angle, a1 = (ring[5] - Vec2(3, 3)).angle
    #expect(sin(a1 - a0) > 0)
}

@Test func ops2DHoleMillSkipsHolesSmallerThanTheTool() throws {
    let paths = [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5), ShapeFactory.circle(center: Vec2(6, 3), radius: 0.1)]
    let (tp, _) = try holeMill(HoleMillParameters(cutDepth: 0.2), paths: paths)
    #expect(tp.metadata["holes"] == "1")
    #expect(tp.metadata["warning"]?.contains("1 hole") == true)
    #expect(throws: CAMError.self) {
        try holeMill(HoleMillParameters(cutDepth: 0.2), paths: [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.05)])
    }
}

@Test func ops2DHoleMillThreadClimbsUpOneTurnPerPitch() throws {
    var p = HoleMillParameters(mode: .thread, cutDepth: 0.5, threadPitch: 0.1)
    p.holeDiameter = 0.75
    let (tp, ctx) = try holeMill(p)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > -0.2 && $0.z < ctx.coords.safeZ - 1e-9 }
    let ring = cut.filter { abs($0.xy.distance(to: Vec2(3, 3)) - 0.25) < 0.001 }
    #expect(!ring.isEmpty)
    // Goes up from the cut depth: 5 turns of 0.1.
    let depths = ring.map { ctx.coords.depth(ofMachineZ: $0.z) }
    #expect(abs(depths.first! - 0.5) < 1e-9)
    #expect(abs(depths.last! - 0.0) < 1e-9)
    #expect(zip(depths, depths.dropFirst()).allSatisfy { $0.1 <= $0.0 + 1e-12 })
    // Total angle swept = 5 turns.
    var sweep = 0.0
    for (a, b) in zip(ring, ring.dropFirst()) {
        var d = (b.xy - Vec2(3, 3)).angle - (a.xy - Vec2(3, 3)).angle
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        sweep += d
    }
    #expect(abs(sweep - 10 * .pi) < 0.01)
    // Never deeper than the cut depth.
    #expect(abs(tp.minZ! + 0.5) < 1e-9)
}

@Test func ops2DHoleMillConventionalThreadEndsAtTheCutDepth() throws {
    var p = HoleMillParameters(mode: .thread, cutDepth: 0.45, threadPitch: 0.1, direction: .conventional)
    p.holeDiameter = 0.75
    let (tp, _) = try holeMill(p)
    #expect(abs(tp.minZ! + 0.45) < 1e-9)
}

@Test func ops2DHoleMillNeverFeedsThroughTheUncutCore() throws {
    // 1" hole, 1/4" tool: the ring leaves a 0.5" core standing in the middle.
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.5))
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let atDepth = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    #expect(!atDepth.isEmpty)
    for q in atDepth { #expect(q.xy.distance(to: Vec2(3, 3)) > 0.375 - 0.001) }

    // 1/2" hole, 1/4" tool: no core, so the tool may move to the centre before lifting.
    var small = HoleMillParameters(cutDepth: 0.3)
    small.holeDiameter = 0.5
    let (tp2, ctx2) = try holeMill(small)
    let centre = F.densePoints(tp2.moves).filter {
        ctx2.coords.depth(ofMachineZ: $0.z) > 1e-9 && $0.xy.distance(to: Vec2(3, 3)) < 1e-9
    }
    #expect(!centre.isEmpty)
}
