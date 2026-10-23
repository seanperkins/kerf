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

/// Issue #96. Raster lines are `span / n` apart, a little closer than the spacing, and were grouped by rounding
/// `offset / spacing`, so two neighbouring lines could land in one group and be cut in the same direction. Each line
/// is its own run, and the runs alternate direction.
@Test(arguments: [(0.08, 1.08, 6), (0.06, 0.09, 2), (0.0, 0.2, 2)])
func textureRowsAreSeparateAndAlternateDirection(bottom: Double, top: Double, rowCount: Int) {
    // The strips narrower than the spacing get a row on each edge, closer together than a quarter of the spacing.
    let region = [[Vec2(0, bottom), Vec2(3, bottom), Vec2(3, top), Vec2(0, top)]]
    let p = TextureParameters(maxDepth: 0.05, spacing: 0.15, minStrokeLength: 0.3, maxStrokeLength: 0.6,
                              angle: 0, variation: 0, seed: 7)
    let strokes = TextureOperation.strokes(in: region, params: p, tolerance: 0.001)
    #expect(!strokes.isEmpty)
    var rows: [(y: Double, direction: Double)] = []
    for s in strokes {
        let y = (s[0].xy.y * 1e4).rounded() / 1e4
        let direction = (s.last!.xy.x - s[0].xy.x) >= 0 ? 1.0 : -1.0
        if let last = rows.last, last.y == y {
            #expect(last.direction == direction, "a row is cut in two directions at y = \(y)")
        } else {
            #expect(!rows.contains { $0.y == y }, "row y = \(y) comes back after another row")
            rows.append((y, direction))
        }
    }
    #expect(rows.count >= rowCount)
    for (a, b) in zip(rows, rows.dropFirst()) {
        #expect(a.direction != b.direction, "rows at y = \(a.y) and \(b.y) run the same way")
    }
}
