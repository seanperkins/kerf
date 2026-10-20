import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func square(_ x: Double, _ y: Double, _ s: Double) -> [Vec2] {
    [Vec2(x, y), Vec2(x + s, y), Vec2(x + s, y + s), Vec2(x, y + s)]
}

/// Two 1" squares profiled outside at (1,1) and (6,1), with `zones` in the document.
private func generate(_ zones: [KeepOutZone], zZero: ZZeroMode = .materialTop,
                      pocket: Bool = false) throws -> (Toolpath, CAMContext) {
    var (ctx, ids) = F.document([F.rect(1, 1, 1, 1), F.rect(6, 1, 1, 1)], zZero: zZero)
    ctx.document.keepOutZones = zones
    let setup = OperationSetup(name: "Cut", toolID: F.endMill.id, shapeIDs: ids)
    let op: AnyOperation = pocket
        ? .pocket(PocketOperation(setup: setup, params: PocketParameters(depth: DepthSettings(cutDepth: 0.25))))
        : .profile(ProfileOperation(setup: setup, params: ProfileParameters(depth: DepthSettings(cutDepth: 0.25))))
    return (try op.generate(in: ctx)[0], ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DKeepOutLiftOverClearsACutZone(mode: ZZeroMode) throws {
    // A clamp over the left edge of the first square's profile.
    let clamp = KeepOutZone(name: "Clamp", outline: square(0.5, 1.3, 0.4), height: 0.5, liftOver: true)
    let (tp, ctx) = try generate([clamp], zZero: mode)
    #expect(KeepOut.violations([tp], zones: [clamp], coords: ctx.coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(Int(tp.metadata["keep-out lifts"] ?? "0")! >= 1)
    // Still cuts the rest of both squares at full depth.
    let cuts = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 0.249 }
    #expect(cuts.contains { ctx.coords.materialXY(fromMachine: $0.xy).x > 6 })
    #expect(cuts.contains { abs(ctx.coords.materialXY(fromMachine: $0.xy).y - 0.875) < 1e-6 })
    // Without lift-over the same zone is only reported.
    var plain = clamp
    plain.liftOver = nil
    let (tp2, ctx2) = try generate([plain], zZero: mode)
    #expect(!KeepOut.violations([tp2], zones: [plain], coords: ctx2.coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(tp2.metadata["keep-out lifts"] == nil)
}

@Test func ops2DKeepOutLiftOverRaisesRapids() throws {
    // A tall clamp between the squares, under the safe-Z rapid.
    let tall = KeepOutZone(name: "Tall", outline: square(3.5, 0.5, 1.5), height: 0.5, liftOver: true)
    let (tp, ctx) = try generate([tall])
    #expect(KeepOut.violations([tp], zones: [tall], coords: ctx.coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(tp.moves.compactMap(\.target).map(\.z).max()! >= ctx.coords.z(aboveTop: 0.6) - 1e-9)
}

@Test func ops2DKeepOutLiftOverPocketAndEndsSafely() throws {
    // Covers the whole second square: the pocket there is skipped entirely, and the toolpath
    // must not end parked over the clamp.
    let clamp = KeepOutZone(name: "Over", outline: square(5.5, 0.5, 2), height: 1, liftOver: true)
    let (tp, ctx) = try generate([clamp], pocket: true)
    #expect(KeepOut.violations([tp], zones: [clamp], coords: ctx.coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let end = try #require(tp.moves.last?.target)
    #expect(ctx.coords.materialXY(fromMachine: end.xy).x < 3)
    let cuts = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-6 }
    #expect(!cuts.isEmpty)
    #expect(!cuts.contains { ctx.coords.materialXY(fromMachine: $0.xy).x > 4 })
}

@Test func ops2DKeepOutLiftOverSplitsArcs() throws {
    // A circle cut on the line with arcs; the zone covers its right side.
    let circle = ShapeFactory.circle(center: Vec2(3, 3), radius: 1)
    var (ctx, ids) = F.document([circle])
    let zone = KeepOutZone(name: "Z", outline: square(3.8, 2.5, 1), height: 0.5, liftOver: true)
    ctx.document.keepOutZones = [zone]
    let op = AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "C", toolID: F.endMill.id, shapeIDs: ids),
                                                   params: ProfileParameters(depth: DepthSettings(cutDepth: 0.2), side: .on)))
    let tp = try op.generate(in: ctx)[0]
    #expect(KeepOut.violations([tp], zones: [zone], coords: ctx.coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let cuts = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 0.199 }
    #expect(cuts.contains { ctx.coords.materialXY(fromMachine: $0.xy).x < 2.1 })
}
