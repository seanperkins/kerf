import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture
private let vBit90 = ToolLibrary.seeded.tools[6] // 90°, 1/2" diameter

private func prism(_ paths: [Path], params: PrismParameters = PrismParameters(), tool: Tool = vBit90,
                   zZero: ZZeroMode = .materialTop) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document(paths, zZero: zZero)
    let tps = try PrismOperation(setup: OperationSetup(name: "Pr", toolID: tool.id, shapeIDs: ids), params: params)
        .generate(in: ctx)
    return (tps[0], ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DPrismDepthPerShapeFromItsWidth(mode: ZZeroMode) throws {
    let narrow = Rect2(x: 1, y: 1, width: 0.4, height: 1)   // inscribed radius 0.2
    let wider = Rect2(x: 3, y: 1, width: 0.3, height: 1)    // inscribed radius 0.15
    let (tp, ctx) = try prism([F.rect(1, 1, 0.4, 1), F.rect(3, 1, 0.3, 1)], zZero: mode)
    #expect(tp.kind == .prism)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    var deepest: [Int: Double] = [:]
    for q in F.densePoints(tp.moves) {
        let d = ctx.coords.depth(ofMachineZ: q.z)
        guard d > 1e-9 else { continue }
        let inNarrow = F.distanceToRectBoundary(q.xy, narrow) < 1e-6
        let inWider = F.distanceToRectBoundary(q.xy, wider) < 1e-6
        #expect(inNarrow || inWider) // the tip stays on the outline
        let k = inNarrow ? 0 : 1
        deepest[k] = max(deepest[k] ?? 0, d)
    }
    // 90° bit: depth = inscribed radius.
    #expect(abs(deepest[0]! - 0.2) < 0.001)
    #expect(abs(deepest[1]! - 0.15) < 0.001)
    #expect(tp.metadata["warning"] == nil)
}

@Test func ops2DPrismLimitsDepthToTheBitAndMaxDepth() throws {
    let (tp, ctx) = try prism([F.rect(1, 1, 2, 2)])
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.25)) < 1e-9)
    #expect(tp.metadata["warning"]?.contains("flat") == true)
    let (capped, _) = try prism([F.rect(1, 1, 0.4, 1)], params: PrismParameters(maxDepth: 0.1))
    #expect(abs(capped.minZ! + 0.1) < 1e-9)
    #expect(throws: CAMError.self) { try prism([F.rect(1, 1, 1, 1)], tool: F.endMill) }
}

@Test func ops2DPrismInscribedRadiusOfARing() {
    let ring = Polygon2D.region(fromLoops: [F.rect(0, 0, 4, 4).flattened(tolerance: 0.001),
                                            F.rect(1, 1, 2, 2).flattened(tolerance: 0.001)])
    // Largest circle sits in a corner: t = √2(1 − t).
    #expect(abs(PrismOperation.inscribedRadius(ring, tolerance: 0.0005) - 2.0.squareRoot() / (1 + 2.0.squareRoot())) < 0.001)
    #expect(PrismOperation.components(ring).count == 1)
    #expect(PrismOperation.components(ring)[0].count == 2)
}
