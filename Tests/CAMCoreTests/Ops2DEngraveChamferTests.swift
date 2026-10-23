import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture
private let vBit60 = ToolLibrary.seeded.tools[5]
private let vBit90 = ToolLibrary.seeded.tools[6]

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DEngraveFollowsVectorsOnTheCentreline(mode: ZZeroMode) throws {
    let line = Path(points: [Vec2(1, 1), Vec2(3, 2), Vec2(5, 1)], closed: false)
    let rect = Rect2(x: 6, y: 1, width: 2, height: 1)
    let (ctx, ids) = F.document([line, F.rect(6, 1, 2, 1)], zZero: mode)
    let op = EngraveOperation(setup: OperationSetup(name: "E", toolID: vBit60.id, shapeIDs: ids),
                              params: EngraveParameters(depth: DepthSettings(cutDepth: 0.0625)))
    let tps = try op.generate(in: ctx)
    #expect(tps.count == 1)
    let tp = tps[0]
    #expect(tp.kind == .engrave)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.0625)) < 1e-9)
    let lineChain = ArcLengthChain(Chain2D(points: [Vec2(1, 1), Vec2(3, 2), Vec2(5, 1)], isClosed: false))
    for p in F.densePoints(tp.moves) where ctx.coords.depth(ofMachineZ: p.z) > 1e-9 {
        let onLine = lineChain.project(p.xy).distance < 1e-6
        let onRect = F.distanceToRectBoundary(p.xy, rect) < 1e-6
        #expect(onLine || onRect)
    }
    let width = 2 * 0.0625 * tan(30 * Double.pi / 180)
    #expect(abs(EngraveOperation.cutWidth(tool: vBit60, depth: 0.0625) - width) < 1e-12)
    #expect(tp.metadata["cut width"] == String(format: "%.4g", width))
}

@Test func ops2DEngraveCutWidthPerToolKind() {
    #expect(EngraveOperation.cutWidth(tool: F.endMill, depth: 0.1) == 0.25)
    let ball = ToolLibrary.seeded.tools[3] // 1/4" ball nose
    #expect(abs(EngraveOperation.cutWidth(tool: ball, depth: 0.125) - 0.25) < 1e-12)
    #expect(EngraveOperation.cutWidth(tool: ball, depth: 0.05) < 0.25)
}

private func chamfer(_ params: ChamferParameters, tool: Tool = vBit90,
                     zZero: ZZeroMode = .materialTop) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document([F.rect(2, 2, 4, 3)], zZero: zZero)
    let op = ChamferOperation(setup: OperationSetup(name: "C", toolID: tool.id, shapeIDs: ids), params: params)
    let tps = try op.generate(in: ctx)
    #expect(tps.count == 1)
    return (tps[0], ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DChamferRunsTheTipOnTheEdgeAtTheWidthDepth(mode: ZZeroMode) throws {
    let rect = Rect2(x: 2, y: 2, width: 4, height: 3)
    let (tp, ctx) = try chamfer(ChamferParameters(width: 0.1), zZero: mode)
    #expect(tp.kind == .chamfer)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    // 90° bit: 0.1 wide needs the tip 0.1 deep, on the vector.
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.1)) < 1e-9)
    for p in F.densePoints(tp.moves) where ctx.coords.depth(ofMachineZ: p.z) > 1e-9 {
        #expect(F.distanceToRectBoundary(p.xy, rect) < 1e-6)
    }
}

@Test func ops2DChamferTipClearanceMovesIntoTheWasteAndDeepens() throws {
    let rect = Rect2(x: 2, y: 2, width: 4, height: 3)
    let p = ChamferParameters(width: 0.1, tipClearance: 0.05)
    let size = try ChamferOperation.size(tool: vBit90, params: p)
    #expect(abs(size.depth - 0.15) < 1e-12)
    #expect(abs(size.width - 0.1) < 1e-12)
    #expect(abs(size.height - 0.1) < 1e-12)
    let (tp, ctx) = try chamfer(p)
    #expect(abs(tp.minZ! + 0.15) < 1e-9)
    let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    for q in cut {
        #expect(!rect.contains(q.xy))
        #expect(abs(F.distanceToRectBoundary(q.xy, rect) - 0.05) < 0.0011)
    }
    // Inside: the tip stays inside the vector instead.
    var inside = p
    inside.side = .inside
    let (tpIn, ctxIn) = try chamfer(inside)
    for q in F.densePoints(tpIn.moves) where ctxIn.coords.depth(ofMachineZ: q.z) > 1e-9 {
        #expect(rect.contains(q.xy))
    }
}

@Test func ops2DChamferDepthModeAndPasses() throws {
    let p = ChamferParameters(depth: 0.25, passDepth: 0.1)
    let size = try ChamferOperation.size(tool: vBit60, params: p)
    #expect(abs(size.width - 0.25 * tan(30 * Double.pi / 180)) < 1e-12)
    let (tp, ctx) = try chamfer(p, tool: vBit60)
    let depths = Set(F.densePoints(tp.moves).map { (ctx.coords.depth(ofMachineZ: $0.z) * 1000).rounded() }.filter { $0 > 0 })
    #expect(depths.count == 3)
    #expect(depths.max() == 250)
}

/// With a start depth the width and the depth share one basis: the surface at the start depth, where the material
/// above is already gone (issue #51). The 90° bit's cone edge runs `depth` out from the tip at that surface, so the
/// width is the depth the tip goes below it.
@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DChamferWidthAndDepthAreMeasuredFromTheStartDepthSurface(mode: ZZeroMode) throws {
    let tip = vBit90.tipDiameter / 2
    // By depth: the tip goes 0.24 below the start depth (0.44 below the top); the width is on the start surface.
    let byDepth = ChamferParameters(depth: 0.24, startDepth: 0.2)
    let size = try ChamferOperation.size(tool: vBit90, params: byDepth)
    #expect(abs(size.depth - 0.24) < 1e-12)
    #expect(abs(size.width - (tip + 0.24)) < 1e-12)
    let (tp, ctx) = try chamfer(byDepth, zZero: mode)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.44)) < 1e-9)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    // By width: asking for the width the depth gave comes back to the same cut.
    let byWidth = ChamferParameters(width: size.width, startDepth: 0.2)
    let same = try ChamferOperation.size(tool: vBit90, params: byWidth)
    #expect(abs(same.depth - size.depth) < 1e-9 && abs(same.width - size.width) < 1e-9)
    let (tpWidth, ctxWidth) = try chamfer(byWidth, zZero: mode)
    #expect(abs(tpWidth.minZ! - ctxWidth.coords.z(depth: 0.44)) < 1e-9)
    // The start depth shifts the cut and nothing else: the same size at the top is the same bevel.
    let atTop = try ChamferOperation.size(tool: vBit90, params: ChamferParameters(depth: 0.24))
    #expect(atTop.depth == size.depth && atTop.width == size.width && atTop.height == size.height)
    #expect(abs(size.tipDepth - atTop.tipDepth - 0.2) < 1e-12)
    // Nothing is cut at or above the start depth: a depth of 0 below it, or less, is refused.
    #expect(throws: CAMError.self) { try ChamferOperation.size(tool: vBit90, params: ChamferParameters(depth: 0, startDepth: 0.2)) }
    #expect(throws: CAMError.self) { try ChamferOperation.size(tool: vBit90, params: ChamferParameters(depth: -0.1, startDepth: 0.2)) }
    // Too wide for the bit is judged on the same surface: 0.3 wide on a 1/2 in bit, whatever the start depth.
    #expect(throws: CAMError.self) { try ChamferOperation.size(tool: vBit90, params: ChamferParameters(width: 0.3, startDepth: 0.2)) }
}

/// A chamfer saved before the basis was chosen has no `basis` key and keeps cutting from the material top, so
/// reopening a job never changes its G-code (issue #51).
@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DChamferSavedWithoutABasisKeepsTheMaterialTop(mode: ZZeroMode) throws {
    let current = ChamferParameters(depth: 0.24, startDepth: 0.2)
    #expect(current.basis == .startSurface)
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
    #expect(json["basis"] as? String == "startSurface")
    json.removeValue(forKey: "basis")
    let old = try JSONDecoder().decode(ChamferParameters.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.basis == .materialTop && old.depth == 0.24 && old.startDepth == 0.2)
    #expect(try JSONDecoder().decode(ChamferParameters.self, from: JSONEncoder().encode(current)) == current)
    // The tip goes 0.24 below the material top and the width is taken there, as it always was.
    let size = try ChamferOperation.size(tool: vBit90, params: old)
    #expect(abs(size.tipDepth - 0.24) < 1e-12 && abs(size.width - (vBit90.tipDiameter / 2 + 0.24)) < 1e-12)
    let (tp, ctx) = try chamfer(old, zZero: mode)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.24)) < 1e-9)
    // Its start depth is not credited to the flute check, as before.
    let rect = F.document([F.rect(2, 2, 4, 3)])
    let op = AnyOperation.chamfer(ChamferOperation(setup: OperationSetup(name: "C", toolID: vBit90.id, shapeIDs: rect.1), params: old))
    #expect(try op.generate(in: rect.0).first?.clearedDepth == nil)
}

/// "Measure from the start depth's surface" keeps the cut: the tip is as deep as it was, whether the chamfer was
/// sized by depth or by width.
@Test func ops2DChamferMeasuredFromTheStartSurfaceCutsTheSameThing() throws {
    for old in [ChamferParameters(depth: 0.24, startDepth: 0.2, basis: .materialTop),
                ChamferParameters(width: 0.1, tipClearance: 0.02, startDepth: 0.05, basis: .materialTop, passDepth: 0.03)] {
        let moved = try ChamferOperation.measuredFromStartSurface(old, tool: vBit90)
        #expect(moved.basis == .startSurface && moved.depth != nil)
        #expect(abs(try ChamferOperation.size(tool: vBit90, params: moved).tipDepth - ChamferOperation.size(tool: vBit90, params: old).tipDepth) < 1e-12)
        let (before, _) = try chamfer(old)
        let (after, _) = try chamfer(moved)
        #expect(before.moves == after.moves)
    }
    let current = ChamferParameters(depth: 0.24, startDepth: 0.2)
    #expect(try ChamferOperation.measuredFromStartSurface(current, tool: vBit90) == current)
}

@Test func ops2DChamferRefusesNegativeAndNonNumericSizes() {
    for p in [ChamferParameters(depth: 0.1, startDepth: -0.1), ChamferParameters(depth: 0.1, startDepth: .nan),
              ChamferParameters(depth: 0.1, tipClearance: .infinity), ChamferParameters(depth: 0.1, tipClearance: .nan),
              ChamferParameters(width: .nan), ChamferParameters(depth: .nan), ChamferParameters(depth: .infinity),
              ChamferParameters(depth: 0.1, startDepth: -0.1, basis: .materialTop)] {
        #expect(throws: CAMError.self, "\(p)") { try ChamferOperation.size(tool: vBit90, params: p) }
    }
}

@Test func ops2DChamferRejectsWrongToolsAndOversizedChamfers() {
    #expect(throws: CAMError.self) { try ChamferOperation.size(tool: F.endMill, params: ChamferParameters()) }
    // 90° bit, 1/2" diameter: the cone reaches at most 0.25 from the tip.
    #expect(throws: CAMError.self) { try ChamferOperation.size(tool: vBit90, params: ChamferParameters(width: 0.3)) }
    #expect(throws: CAMError.self) { try chamfer(ChamferParameters(), tool: F.endMill) }
}

@Test func ops2DNewOperationsRoundTripThroughAnyOperation() throws {
    let setup = OperationSetup(name: "X", toolID: vBit90.id)
    let ops: [AnyOperation] = [.engrave(EngraveOperation(setup: setup)), .chamfer(ChamferOperation(setup: setup))]
    let back = try JSONDecoder().decode([AnyOperation].self, from: JSONEncoder().encode(ops))
    #expect(back == ops)
    #expect(back.map(\.kind) == [.engrave, .chamfer])
}
