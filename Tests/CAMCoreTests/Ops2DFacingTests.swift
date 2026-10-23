import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// A 6 × 4 in sheet, so coverage can be sampled on a fine grid.
private func facing(_ params: FacingParameters, paths: [Path] = [], tool: Tool = F.bigEndMill,
                    zZero: ZZeroMode = .materialTop, sheet: Vec2 = Vec2(6, 4)) throws -> (Toolpath, CAMContext) {
    let (made, ids) = F.document(paths, zZero: zZero)
    var ctx = made
    ctx.document.job.width = sheet.x
    ctx.document.job.height = sheet.y
    let tps = try FacingOperation(setup: OperationSetup(name: "Face", toolID: tool.id, shapeIDs: ids), params: params)
        .generate(in: ctx)
    #expect(tps.count == 1)
    return (tps[0], ctx)
}

/// The straight cuts at `depth`: where the tool center travels while it is down at that depth.
private func cuts(_ tp: Toolpath, at depth: Double, coords: MachineCoordinates) -> [(Vec2, Vec2)] {
    var out: [(Vec2, Vec2)] = []
    var cur: Vec3?
    for m in tp.moves {
        if case .linear(let p, _) = m, let c = cur, abs(coords.depth(ofMachineZ: p.z) - depth) < 1e-9,
           abs(coords.depth(ofMachineZ: c.z) - depth) < 1e-9 {
            out.append((c.xy, p.xy))
        }
        if let t = m.target { cur = t }
    }
    return out
}

/// The worst distance from a point of `area` (sampled every `grid`) to the tool-center path.
private func worstGap(_ segments: [(Vec2, Vec2)], over area: Rect2, grid: Double = 0.05) -> Double {
    var worst = 0.0
    var x = area.min.x
    while x <= area.max.x + 1e-9 {
        var y = area.min.y
        while y <= area.max.y + 1e-9 {
            let p = Vec2(min(x, area.max.x), min(y, area.max.y))
            let d = segments.map { Polygon2D.closestPoint(onSegment: $0.0, $0.1, to: p).0.distance(to: p) }.min() ?? .infinity
            worst = max(worst, d)
            y += grid
        }
        x += grid
    }
    return worst
}

private let sheet = Rect2(x: 0, y: 0, width: 6, height: 4)

@Test(arguments: [FacingPattern.rasterX, .rasterY, .spiral], [ZZeroMode.materialTop, .spoilboard])
func ops2DFacingCoversTheWholeMaterialToTheEdge(pattern: FacingPattern, mode: ZZeroMode) throws {
    let (tp, ctx) = try facing(FacingParameters(pattern: pattern), zZero: mode)
    #expect(tp.kind == .facing)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.0625)) < 1e-9)
    let r = F.bigEndMill.radius
    let gap = worstGap(cuts(tp, at: 0.0625, coords: ctx.coords), over: sheet)
    #expect(gap <= r + 1e-6, "an uncut spot \(gap) from the path, tool radius \(r)")
    #expect(tp.metadata["warning"] == nil)
}

@Test(arguments: [FacingPattern.rasterX, .rasterY, .spiral], [Vec2(6, 4), Vec2(6, 0.9), Vec2(0.3, 4), Vec2(2.6, 2.6), Vec2(5.3, 1.7), Vec2(2, 2), Vec2(3.4, 2), Vec2(2, 3.4)])
func ops2DFacingCoversAnyAreaTheToolLeavesNothing(pattern: FacingPattern, size: Vec2) throws {
    // Sizes from wider than the tool to narrower than it, through ones where a spiral's rings leave a core (2 × 2: a
    // last ring 0.6 square, a cutter-width core the ring alone misses).
    let box = Rect2(x: 0.7, y: 0.4, width: size.x, height: size.y)
    var p = FacingParameters(area: .vectors, pattern: pattern)
    p.overhang = nil
    let (tp, ctx) = try facing(p, paths: [F.rect(box.min.x, box.min.y, size.x, size.y)], sheet: Vec2(8, 6))
    let gap = worstGap(cuts(tp, at: 0.0625, coords: ctx.coords), over: box)
    #expect(gap <= F.bigEndMill.radius + 1e-6, "an uncut spot \(gap) from the path")
}

@Test func ops2DFacingRasterPassesRunAlongTheChosenAxis() throws {
    for (pattern, alongX) in [(FacingPattern.rasterX, true), (.rasterY, false)] {
        let (tp, ctx) = try facing(FacingParameters(pattern: pattern))
        let segs = cuts(tp, at: 0.0625, coords: ctx.coords)
        // Long cuts follow the axis; the short joins between them run across it, past the area.
        let long = segs.filter { $0.0.distance(to: $0.1) > 2 }
        #expect(long.count >= 5)
        for (a, b) in long { #expect(alongX ? abs(a.y - b.y) < 1e-9 : abs(a.x - b.x) < 1e-9) }
        // Neighbouring passes alternate direction.
        let signs = long.map { alongX ? ($0.1.x - $0.0.x) : ($0.1.y - $0.0.y) }.map { $0 > 0 }
        for (a, b) in zip(signs, signs.dropFirst()) { #expect(a != b) }
        // Passes are no farther apart than the stepover: 70% of the tool.
        let rows = long.map { alongX ? $0.0.y : $0.0.x }
        for (a, b) in zip(rows, rows.dropFirst()) { #expect(abs(b - a) <= F.bigEndMill.diameter * 0.7 + 1e-9) }
    }
}

@Test func ops2DFacingEnterAndLeaveClearOfTheStock() throws {
    // The tool goes down outside the material, so the first pass is fed in, not plunged into the surface.
    for pattern in [FacingPattern.rasterX, .rasterY, .spiral] {
        let (tp, ctx) = try facing(FacingParameters(pattern: pattern))
        let r = F.bigEndMill.radius
        var cur: Vec3?
        var firstPlunge: Vec2?
        for m in tp.moves {
            if case .linear(let p, _) = m, let c = cur, p.z < c.z - 1e-9, firstPlunge == nil { firstPlunge = p.xy }
            if let t = m.target { cur = t }
        }
        let plunge = try #require(firstPlunge)
        // The cutter at the plunge touches no part of the sheet.
        let nearest = Vec2(min(max(plunge.x, 0), 6), min(max(plunge.y, 0), 4))
        #expect(plunge.distance(to: nearest) >= r - 1e-9, "\(pattern) plunges at \(plunge) inside the stock")
        if pattern != .spiral {
            // The last cut ends clear of the stock too, where the cutter lifts out.
            let last = try #require(F.densePoints(tp.moves).last)
            let nearestToLast = Vec2(min(max(last.x, 0), 6), min(max(last.y, 0), 4))
            #expect(last.xy.distance(to: nearestToLast) >= r - 1e-9)
        }
        #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    }
}

@Test func ops2DFacingSpiralTurnsClockwiseForClimbAndTheOtherWayConventionally() throws {
    for (direction, clockwise) in [(CutDirection.climb, true), (.conventional, false)] {
        let (tp, ctx) = try facing(FacingParameters(pattern: .spiral, direction: direction))
        let ring = cuts(tp, at: 0.0625, coords: ctx.coords).prefix(4)
        // Signed area of the outer ring (the first four sides): negative = clockwise.
        let pts = ring.map(\.0)
        var area = 0.0
        for i in pts.indices { let a = pts[i], b = pts[(i + 1) % pts.count]; area += a.x * b.y - b.x * a.y }
        #expect((area < 0) == clockwise)
    }
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DFacingTakesTheCutInPassesAndKeepsEveryLayerTheSame(mode: ZZeroMode) throws {
    var p = FacingParameters(pattern: .rasterX, depth: DepthSettings(cutDepth: 0.5))
    p.stepover = 0.5
    let (tp, ctx) = try facing(p, zZero: mode)
    // Stepdown 0.2 (the 1/2" end mill's) → three passes ending at the cut depth.
    let planned = p.depth.passDepths(toolStepdown: F.bigEndMill.stepdown)
    #expect(planned.count == 3)
    #expect(abs((planned.last ?? 0) - 0.5) < 1e-9)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.5)) < 1e-9)
    let found = Set(F.densePoints(tp.moves).map { (ctx.coords.depth(ofMachineZ: $0.z) * 1e6).rounded() }.filter { $0 > 1 })
    #expect(found == Set(planned.map { ($0 * 1e6).rounded() }))
    // Every layer is cut over the whole area.
    for d in planned {
        let gap = worstGap(cuts(tp, at: d, coords: ctx.coords), over: sheet, grid: 0.2)
        #expect(gap <= F.bigEndMill.radius + 1e-6)
    }
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
}

@Test func ops2DFacingOverhangMovesTheCuttersEdgeNotTheLead() throws {
    // Overhang 0.4 on a 0.25 radius: the center runs 0.15 past the edge on each side.
    var p = FacingParameters(pattern: .rasterX)
    p.overhang = 0.4
    let (tp, ctx) = try facing(p)
    let segs = cuts(tp, at: 0.0625, coords: ctx.coords)
    let ys = segs.flatMap { [$0.0.y, $0.1.y] }
    #expect(abs((ys.min() ?? 0) - (-0.15)) < 1e-9)
    #expect(abs((ys.max() ?? 0) - 4.15) < 1e-9)
    // A bigger overhang is not a warning when the area is the whole material.
    #expect(tp.metadata["warning"] == nil)
}

@Test func ops2DFacingWarnsWhenOverhangCannotReachTheCorners() throws {
    var p = FacingParameters(pattern: .rasterX)
    p.overhang = 0
    let (tp, _) = try facing(p)
    #expect(tp.metadata["warning"]?.contains("corners") == true)
    // The smallest overhang that squares the corners (r × (1 − 1/√2)) is clean.
    p.overhang = F.bigEndMill.radius * (1 - 1 / 2.0.squareRoot()) + 0.001
    let (ok, _) = try facing(p)
    #expect(ok.metadata["warning"] == nil)
}

@Test func ops2DFacingASelectedAreaInsideTheStockWarnsThatTheCutterReachesPastIt() throws {
    var p = FacingParameters(area: .vectors, pattern: .rasterX)
    p.overhang = nil
    let (tp, _) = try facing(p, paths: [F.rect(1, 1, 3, 2)])
    #expect(tp.metadata["warning"]?.contains("not being faced") == true)
    // The whole material, or a box that is the whole material, has nothing beyond it.
    let (all, _) = try facing(p, paths: [F.rect(0, 0, 6, 4)])
    #expect(all.metadata["warning"] == nil)
}

@Test func ops2DFacingAreaFollowsTheBoundingBoxOfEveryVector() throws {
    let (tp, ctx) = try facing(FacingParameters(area: .vectors, pattern: .rasterX),
                               paths: [F.rect(1, 1, 1, 1), F.rect(3.5, 2, 1, 1)])
    // The box is x 1…4.5, y 1…3: the passes run from y 1 to y 3 (the center rides the edges).
    let ys = cuts(tp, at: 0.0625, coords: ctx.coords).flatMap { [$0.0.y, $0.1.y] }
    #expect(abs((ys.min() ?? 0) - 1) < 1e-9)
    #expect(abs((ys.max() ?? 0) - 3) < 1e-9)
    #expect(tp.metadata["area"] == "3.5 in × 2 in")
}

@Test func ops2DFacingExplainsWhereTheTopIsAfterwards() throws {
    let (top, _) = try facing(FacingParameters(depth: DepthSettings(cutDepth: 0.1)), zZero: .materialTop)
    #expect(top.metadata["note"]?.contains("do not re-zero") == true)
    #expect(top.metadata["note"]?.contains("0.65 in thick") == true)
    let (bed, _) = try facing(FacingParameters(depth: DepthSettings(cutDepth: 0.1)), zZero: .spoilboard)
    #expect(bed.metadata["note"]?.contains("spoilboard") == true)
}

@Test func ops2DFacingRefusesSettingsThatCannotFaceAnything() {
    func fails(_ edit: (inout FacingParameters) -> Void, paths: [Path] = []) {
        var p = FacingParameters()
        edit(&p)
        #expect(throws: CAMError.self) { try facing(p, paths: paths) }
    }
    fails { $0.stepover = 0 }
    fails { $0.stepover = 1 }
    fails { $0.stepover = .nan }
    fails { $0.overhang = -0.1 }
    fails { $0.overhang = .infinity }
    fails { $0.depth.cutDepth = 0 }
    fails { $0.depth.cutDepth = .nan }
    fails { $0.depth.passDepth = 0 }
    // The selected vectors give the area; none selected gives none.
    fails({ $0.area = .vectors })
    // A tiny stepover is a typo, not a request for a million passes.
    fails { $0.stepover = 1e-9 }
}

@Test func ops2DFacingSurvivesSavingAndCreditsTheStartDepth() throws {
    let (made, _) = F.document([])
    var ctx = made
    ctx.document.job.width = 6
    ctx.document.job.height = 4
    var params = FacingParameters(pattern: .spiral, depth: DepthSettings(startDepth: 0.1, cutDepth: 0.2), overhang: 0.3)
    params.stepover = 0.6
    let op = AnyOperation.facing(FacingOperation(setup: OperationSetup(name: "Face", toolID: F.bigEndMill.id), params: params))
    let data = try JSONEncoder().encode(op)
    let back = try JSONDecoder().decode(AnyOperation.self, from: data)
    #expect(back == op)
    #expect(back.kind == .facing)
    // The material above the start depth is already gone: the flute check measures from there.
    let tps = try back.generate(in: ctx)
    #expect(tps.first?.clearedDepth == 0.1)
}
