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
