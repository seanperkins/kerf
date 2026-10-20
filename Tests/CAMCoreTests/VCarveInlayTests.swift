import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = VCarveFixture

private func inlay(_ paths: [Path], _ params: InlayParameters, zZero: ZZeroMode = .materialTop) throws
    -> (tps: [Toolpath], ctx: CAMContext) {
    let (ctx, setup) = F.context(paths, zZero: zZero)
    return (try InlayOperation(setup: setup, params: params).generate(in: ctx), ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func inlayFemaleAndMaleDepths(zZero: ZZeroMode) throws {
    let params = InlayParameters(part: .both, pocketDepth: 0.2, maleStartDepth: 0.1, glueGap: 0.02)
    let (tps, ctx) = try inlay([F.rect(1, 1, 1, 1)], params, zZero: zZero)
    #expect(tps.map(\.name) == ["V Female", "V Male"])
    let coords = ctx.coords
    let female = F.cutPoints(tps[0], coords: coords), male = F.cutPoints(tps[1], coords: coords)
    #expect(abs((female.map(\.depth).max() ?? 0) - 0.2) < 1e-6)
    #expect(abs((male.map(\.depth).max() ?? 0) - 0.2) < 1e-6)
    #expect(male.allSatisfy { $0.depth >= 0.1 - 1e-6 })   // start depth everywhere
    #expect(tps[1].metadata["bottomGap"] == "0.1000")
    for tp in tps { F.expectSafeMotion(tp, coords: coords) }
}

@Test func inlayPlugWallsMatchPocketWalls() throws {
    // Seated with its top S below the female surface, the plug's surface at every point
    // near the wall coincides with the pocket's: removedFemale(q) + removedMale(mirror q) = S.
    let s = 0.1
    let params = InlayParameters(part: .both, pocketDepth: 0.2, maleStartDepth: s, glueGap: 0.02)
    let (tps, ctx) = try inlay([F.rect(1, 1, 1, 1)], params)
    let female = F.cutPoints(tps[0], coords: ctx.coords), male = F.cutPoints(tps[1], coords: ctx.coords)
    for a in [0.01, 0.03, 0.05] {
        for y in [1.3, 1.5, 1.7] {
            let q = Vec2(1 + a, y), mirrored = Vec2(2 - a, y)
            let sum = F.removedDepth(at: q, by: female, slope: F.tan30)
                + F.removedDepth(at: mirrored, by: male, slope: F.tan30)
            #expect(abs(sum - s) < 0.01, "a=\(a) y=\(y) sum=\(sum)")
        }
    }
}

@Test func inlayMaleIsMirrored() throws {
    // Right triangle with the right angle at (1,1); mirrored about x = 1.5 it has it at (2,1).
    let tri = Path(points: [Vec2(1, 1), Vec2(2, 1), Vec2(1, 2)], closed: true)
    let (tps, ctx) = try inlay([tri], InlayParameters(part: .male))
    #expect(tps.count == 1)
    let male = F.cutPoints(tps[0], coords: ctx.coords)
    // Inside the mirrored triangle (plug) nothing is removed...
    #expect(F.removedDepth(at: Vec2(1.85, 1.2), by: male, slope: F.tan30) < 1e-6)
    // ...while the same spot of the un-mirrored outline's complement is cleared deep.
    #expect(F.removedDepth(at: Vec2(1.1, 1.8), by: male, slope: F.tan30) > 0.15)
    // The waste is cleared out to the boundary margin.
    #expect(tps[0].xyBounds.max.x > 2.1 && tps[0].xyBounds.min.x < 0.9)
}

@Test func inlayWithClearanceToolOrdersToolsPerPart() throws {
    let params = InlayParameters(part: .both, pocketDepth: 0.2, maleStartDepth: 0.1, glueGap: 0.02,
                                 flatClearanceToolID: F.endMill.id, maleBoundaryMargin: 0.5)
    let (tps, ctx) = try inlay([F.rect(1, 1, 1.5, 1.5)], params)
    #expect(tps.map(\.tool.id) == [F.endMill.id, F.vbit60.id, F.endMill.id, F.vbit60.id])
    #expect(tps.map { $0.metadata["part"] ?? "" } == ["female", "female", "male", "male"])
    for tp in tps {
        #expect(abs(ctx.coords.depth(ofMachineZ: tp.minZ!) - 0.2) < 1e-6)
        F.expectSafeMotion(tp, coords: ctx.coords)
    }
}

@Test func inlayRejectsStartDepthLeavingNoGlueGap() {
    #expect(throws: CAMError.self) {
        _ = try inlay([F.rect(0, 0, 1, 1)], InlayParameters(pocketDepth: 0.2, maleStartDepth: 0.19, glueGap: 0.02))
    }
}

@Test func inlayFemaleOnlyMatchesVCarveWithFlatDepth() throws {
    let (tps, ctx) = try inlay([F.rect(0, 0, 0.8, 0.6)], InlayParameters(part: .female, pocketDepth: 0.15))
    let (vctx, setup) = F.context([F.rect(0, 0, 0.8, 0.6)])
    let v = try VCarveOperation(setup: setup, params: VCarveParameters(flatDepth: 0.15)).generate(in: vctx)
    #expect(tps.count == 1 && v.count == 1)
    #expect(tps[0].moves == v[0].moves)
    _ = ctx
}
