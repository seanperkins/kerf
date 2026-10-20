import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = VCarveFixture

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func vcarveRectangleReachesHalfWidthOverTanHalfAngle(zZero: ZZeroMode) throws {
    let (ctx, setup) = F.context([F.rect(2, 3, 0.4, 0.3)], zZero: zZero)
    let tps = try VCarveOperation(setup: setup).generate(in: ctx)
    #expect(tps.count == 1)
    let tp = try #require(tps.first)
    let expected = 0.15 / F.tan30
    let coords = ctx.coords
    let deepest = try #require(tp.minZ)
    #expect(abs(coords.depth(ofMachineZ: deepest) - expected) < 1e-3)
    // The deepest cut runs along the centre line y = 3.15 between x = 2.15 and 2.25.
    let deep = F.cutPoints(tp, coords: coords).filter { $0.depth > expected - 1e-3 }
    #expect(!deep.isEmpty)
    for p in deep {
        #expect(abs(p.xy.y - 3.15) < 2e-3)
        #expect(p.xy.x > 2.15 - 2e-3 && p.xy.x < 2.25 + 2e-3)
    }
    // Every cut point stays inside the rectangle; depth follows r / tan(30°).
    for p in F.cutPoints(tp, coords: coords) {
        let r = min(p.xy.x - 2, 2.4 - p.xy.x, p.xy.y - 3, 3.3 - p.xy.y)
        #expect(r > -1e-3)
        #expect(abs(p.depth - r / F.tan30) < 5e-3)
    }
    F.expectSafeMotion(tp, coords: coords)
    #expect(tp.tool.id == F.vbit60.id)
}

@Test func vcarveHonoursXYOrigin() throws {
    let (ctx, setup) = F.context([F.rect(2, 3, 0.4, 0.3)], origin: .center)
    let tp = try #require(try VCarveOperation(setup: setup).generate(in: ctx).first)
    let b = tp.xyBounds
    let shift = ctx.document.job.originInMaterialFrame
    #expect(b.min.x >= 2 - shift.x - 1e-6 && b.max.x <= 2.4 - shift.x + 1e-6)
    #expect(b.min.y >= 3 - shift.y - 1e-6 && b.max.y <= 3.3 - shift.y + 1e-6)
}

@Test func vcarveStartDepthShiftsEveryCut() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 0.4, 0.3)])
    let tp = try #require(try VCarveOperation(setup: setup, params: VCarveParameters(startDepth: 0.05)).generate(in: ctx).first)
    let pts = F.cutPoints(tp, coords: ctx.coords)
    #expect(pts.allSatisfy { $0.depth >= 0.05 - 1e-6 })
    #expect(abs((pts.map(\.depth).max() ?? 0) - (0.05 + 0.15 / F.tan30)) < 1e-3)
}

@Test func vcarveNeverExceedsFlatDepth() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 1.0, 0.6)])
    let tps = try VCarveOperation(setup: setup, params: VCarveParameters(flatDepth: 0.1)).generate(in: ctx)
    #expect(tps.count == 1)
    let tp = try #require(tps.first)
    let pts = F.cutPoints(tp, coords: ctx.coords)
    #expect(pts.allSatisfy { $0.depth <= 0.1 + 1e-6 })
    #expect(abs((pts.map(\.depth).max() ?? 0) - 0.1) < 1e-6)
    // Flat floor is cleared by the V-bit: a point well inside the flat area is reached at 0.1.
    #expect(abs(F.removedDepth(at: Vec2(0.5, 0.3), by: pts, slope: F.tan30) - 0.1) < 0.02)
    F.expectSafeMotion(tp, coords: ctx.coords)
}

@Test(arguments: [PocketStrategy.offset, .raster(angle: 0, profilePass: true)])
func vcarveFlatAreaUsesClearanceTool(strategy: PocketStrategy) throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 1.5, 1.0)], zZero: .spoilboard)
    let params = VCarveParameters(flatDepth: 0.15, flatClearanceToolID: F.endMill.id, flatClearanceStrategy: strategy)
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    #expect(tps.map(\.tool.id) == [F.endMill.id, F.vbit60.id])
    let coords = ctx.coords
    for tp in tps {
        #expect(abs(coords.depth(ofMachineZ: tp.minZ!) - 0.15) < 1e-6)
        F.expectSafeMotion(tp, coords: coords)
    }
    // End mill centre stays flatRadius + toolRadius inside the vector.
    let inset = 0.15 * F.tan30 + F.endMill.radius
    for p in F.cutPoints(tps[0], coords: coords) {
        let r = min(p.xy.x, 1.5 - p.xy.x, p.xy.y, 1.0 - p.xy.y)
        #expect(r > inset - 2e-3)
    }
    // The flat area's centre is cleared by the end mill.
    let clr = F.cutPoints(tps[0], coords: coords)
    #expect(clr.contains { $0.xy.distance(to: Vec2(0.75, 0.5)) < F.endMill.radius && $0.depth > 0.15 - 1e-6 })
}

@Test func vcarveMultiPassStepsDown() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 0.4, 0.3)])
    let tp = try #require(try VCarveOperation(setup: setup, params: VCarveParameters(passDepth: 0.1)).generate(in: ctx).first)
    let total = 0.15 / F.tan30   // 0.2598 → 3 passes of 0.0866
    let plungeDepths = tp.moves.enumerated().compactMap { i, m -> Double? in
        guard i > 0, tp.moves[i - 1].isRapid, case .linear(let t, _) = m else { return nil }
        return t.z
    }
    #expect(plungeDepths.count >= 3)
    // The first pass is clamped at total / 3.
    let firstPassEnd = tp.moves.firstIndex { m in
        if case .rapid = m { return false }; return (m.target?.z ?? 0) < -(total / 3) - 1e-6
    }
    let firstLevel = tp.moves.prefix(firstPassEnd ?? tp.moves.count).compactMap { $0.target?.z }.min() ?? 0
    #expect(abs(firstLevel + total / 3) < 1e-6)
    #expect(abs(tp.minZ! + total) < 1e-3)
    F.expectSafeMotion(tp, coords: ctx.coords)
}

@Test func vcarveLetterWithHoleKeepsOutOfCounter() throws {
    // An "O": outer r = 0.3, counter r = 0.15 (given as a second, nested contour).
    let c = Vec2(1, 1)
    let (ctx, setup) = F.context([F.circle(c, 0.3), F.circle(c, 0.15)])
    let tp = try #require(try VCarveOperation(setup: setup).generate(in: ctx).first)
    let pts = F.cutPoints(tp, coords: ctx.coords)
    #expect(!pts.isEmpty)
    for p in pts {
        let d = p.xy.distance(to: c)
        #expect(d > 0.15 - 2e-3 && d < 0.3 + 2e-3)
    }
    // Stroke width 0.15 → max depth 0.075 / tan 30°, along the r = 0.225 circle.
    let maxDepth = pts.map(\.depth).max() ?? 0
    #expect(abs(maxDepth - 0.075 / F.tan30) < 3e-3)
    // The counter is never cut, the ring all the way round is.
    #expect(F.removedDepth(at: c, by: pts, slope: F.tan30) == 0)
    for k in 0..<8 {
        let a = Double(k) * .pi / 4
        let q = c + Vec2(cos(a), sin(a)) * 0.225
        #expect(F.removedDepth(at: q, by: pts, slope: F.tan30) > 0.12)
    }
}

@Test func vcarveRejectsNonVTool() throws {
    var (ctx, setup) = F.context([F.rect(0, 0, 1, 1)])
    setup.toolID = F.endMill.id
    ctx.tolerance = 0.001
    #expect(throws: CAMError.self) { try VCarveOperation(setup: setup).generate(in: ctx) }
}

@Test func vcarveWithoutSelectionThrowsNoGeometry() {
    let (ctx, _) = F.context([F.rect(0, 0, 1, 1)])
    let op = VCarveOperation(setup: OperationSetup(name: "V", toolID: F.vbit60.id))
    #expect(throws: CAMError.noGeometry) { try op.generate(in: ctx) }
}

@Test func vcarveWideAreaIsLimitedByBitAndWarns() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 2, 2)])
    let tp = try #require(try VCarveOperation(setup: setup).generate(in: ctx).first)
    let maxDepth = F.vbit60.radius / F.tan30
    #expect(abs(ctx.coords.depth(ofMachineZ: tp.minZ!) - maxDepth) < 1e-6)
    #expect(tp.metadata["warning"] != nil)
}

@Test func vcarveMillimetreDocument() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 10, 8)], units: .millimeter)
    let tp = try #require(try VCarveOperation(setup: setup).generate(in: ctx).first)
    #expect(abs(ctx.coords.depth(ofMachineZ: tp.minZ!) - 4 / F.tan30) < 0.02)
    #expect(tp.tool.units == .millimeter)
}
