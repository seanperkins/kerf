import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture
private let ballNose = ToolLibrary.seeded.tools[3]
private let vBit = ToolLibrary.seeded.tools[5]

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DFlutingRampsBothEnds(mode: ZZeroMode) throws {
    let line = Path(points: [Vec2(1, 1), Vec2(9, 1)], closed: false)
    let (ctx, ids) = F.document([line], zZero: mode)
    let op = FlutingOperation(setup: OperationSetup(name: "Flute", toolID: ballNose.id, shapeIDs: ids),
                              params: FlutingParameters(depth: DepthSettings(cutDepth: 0.2), ramp: .both,
                                                        rampFraction: 0.25, smoothRamp: true))
    let tp = try op.generate(in: ctx)[0]
    let c = ctx.coords
    #expect(F.conventionViolations(tp, coords: c).isEmpty)
    #expect(abs(tp.minZ! - c.z(depth: 0.2)) < 1e-9)
    let cuts = F.densePoints(tp.moves).filter { $0.z < c.materialTopZ - 1e-9 }
    // Full depth only in the middle half; shallow near the ends.
    for p in cuts where abs(p.z - c.z(depth: 0.2)) < 1e-9 {
        #expect(p.x >= 3 - 1e-6 && p.x <= 7 + 1e-6)
    }
    for p in cuts where p.x < 1.2 || p.x > 8.8 {
        #expect(c.depth(ofMachineZ: p.z) < 0.02)
    }
    // Two passes (0.2 / stepdown 0.1), cut back and forth with a single plunge.
    #expect(tp.moves.filter(\.isRapid).count <= 3)
}

@Test func ops2DFlutingStartRampEndsAtFullDepth() throws {
    let line = Path(points: [Vec2(0, 0), Vec2(4, 0)], closed: false)
    let (ctx, ids) = F.document([line])
    let op = FlutingOperation(setup: OperationSetup(name: "Flute", toolID: vBit.id, shapeIDs: ids),
                              params: FlutingParameters(depth: DepthSettings(cutDepth: 0.1), ramp: .start,
                                                        rampFraction: 0.5, smoothRamp: false))
    let tp = try op.generate(in: ctx)[0]
    let cuts = F.densePoints(tp.moves).filter { $0.z < -1e-9 }
    #expect(cuts.contains { abs($0.x - 4) < 1e-9 && abs($0.z + 0.1) < 1e-9 })
    // Linear ramp: at x = 1 the depth is half.
    #expect(cuts.allSatisfy { $0.x >= 2 - 1e-9 || abs(-$0.z - 0.1 * $0.x / 2) < 1e-6 })
}

@Test func ops2DTextureIsDeterministicShallowAndInside() throws {
    let rect = Rect2(x: 0, y: 0, width: 6, height: 4)
    let (ctx, ids) = F.document([F.rect(0, 0, 6, 4)])
    let params = TextureParameters(maxDepth: 0.05, spacing: 0.2, minStrokeLength: 0.5, maxStrokeLength: 1.5,
                                   angle: 20, variation: 0.6, seed: 42)
    let op = TextureOperation(setup: OperationSetup(name: "Tex", toolID: vBit.id, shapeIDs: ids), params: params)
    let a = try op.generate(in: ctx)[0]
    let b = try op.generate(in: ctx)[0]
    #expect(a.moves == b.moves)
    #expect(F.conventionViolations(a, coords: ctx.coords).isEmpty)
    #expect(Int(a.metadata["strokes"] ?? "0")! > 20)
    #expect(a.minZ! >= -0.05 - 1e-9)
    for p in F.densePoints(a.moves) where p.z < 0 { #expect(rect.contains(p.xy)) }
    var other = op
    other.params.seed = 7
    #expect(try other.generate(in: ctx)[0].moves != a.moves)
}
