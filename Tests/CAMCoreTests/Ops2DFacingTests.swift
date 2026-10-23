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

@Test(arguments: [FacingPattern.rasterX, .rasterY, .spiral], [Double?.none, 0.2, 0.1, 0.0, 0.4, 0.8])
func ops2DFacingEnterAndLeaveClearOfTheStock(pattern: FacingPattern, overhang: Double?) throws {
    // The tool goes down outside the material, so the first pass is fed in, not plunged into the surface, however
    // little the cutter's edge is to reach past the area (overhang 0.2 on a 0.25 radius puts the first cut inside it).
    var p = FacingParameters(pattern: pattern)
    p.overhang = overhang
    let (tp, ctx) = try facing(p)
    let r = F.bigEndMill.radius
    func clearance(_ q: Vec2) -> Double { q.distance(to: Vec2(min(max(q.x, 0), 6), min(max(q.y, 0), 4))) }
    var cur: Vec3?
    var firstPlunge: Vec2?
    for m in tp.moves {
        if case .linear(let q, _) = m, let c = cur, q.z < c.z - 1e-9, firstPlunge == nil { firstPlunge = q.xy }
        if let t = m.target { cur = t }
    }
    let plunge = try #require(firstPlunge)
    #expect(clearance(plunge) >= r - 1e-9, "\(pattern), overhang \(String(describing: overhang)): plunges at \(plunge), inside the stock")
    if pattern != .spiral {
        // A raster's last cut ends clear of the stock too, where the cutter lifts out (a spiral ends in the middle of the
        // faced floor and lifts there).
        let last = try #require(F.densePoints(tp.moves).last)
        #expect(clearance(last.xy) >= r - 1e-9, "lifts out at \(last.xy)")
    }
    // Still the whole material, whatever the overhang that leaves the corners square.
    if (overhang ?? r) >= 0.1 {
        #expect(worstGap(cuts(tp, at: 0.0625, coords: ctx.coords), over: sheet) <= r + 1e-6)
    }
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
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

@Test func ops2DFacingSplitsTheLayerByTheToolsStepdown() throws {
    // The default 1/16 in layer on a tool whose stepdown is 0.03 is three passes, none deeper than that.
    let (made, _) = F.document([])
    var ctx = made
    ctx.document.job.width = 6
    ctx.document.job.height = 4
    var lib = ToolLibrary.seeded
    let i = try #require(lib.tools.firstIndex { $0.id == F.bigEndMill.id })
    lib.tools[i].stepdown = 0.03
    ctx.tools = lib
    let tp = try FacingOperation(setup: OperationSetup(name: "Face", toolID: F.bigEndMill.id)).generate(in: ctx)[0]
    let depths = Array(Set(F.densePoints(tp.moves).map { (ctx.coords.depth(ofMachineZ: $0.z) * 1e6).rounded() / 1e6 }.filter { $0 > 1e-9 })).sorted()
    #expect(depths.count == 3)
    for (a, b) in zip([0.0] + depths, depths) { #expect(b - a <= 0.03 + 1e-9) }
    #expect(abs((depths.last ?? 0) - 0.0625) < 1e-9)
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

@Test func ops2DFacingWarnsHoweverFarTheOverhangReachesIntoSurroundingStock() throws {
    // The cutter's edge goes `overhang` past the box and the lead-in a radius further: 0.75 here is three radii.
    for overhang in [0.0, 0.25, 0.75, 1.5] {
        var p = FacingParameters(area: .vectors, pattern: .rasterX)
        p.overhang = overhang
        let (tp, _) = try facing(p, paths: [F.rect(2, 1.5, 2, 1)])
        #expect(tp.metadata["warning"]?.contains("not being faced") == true, "overhang \(overhang)")
    }
    // On the whole material the same overhangs reach only air.
    for overhang in [0.25, 0.75, 1.5] {
        var p = FacingParameters(pattern: .rasterX)
        p.overhang = overhang
        let (tp, _) = try facing(p)
        #expect(tp.metadata["warning"] == nil, "overhang \(overhang)")
    }
}

@Test(arguments: [FacingPattern.rasterX, .rasterY, .spiral])
func ops2DFacingAVeryLongNarrowAreaStaysSmall(pattern: FacingPattern) throws {
    // A spiral's rings are bounded by the short side (five points each), a raster along the strip's length has a few rows:
    // a long strip is a handful of passes, however long. Rows across it would be a hundred thousand, which is refused.
    if pattern == .rasterY {
        #expect(throws: CAMError.self) { try facing(FacingParameters(pattern: pattern), sheet: Vec2(100_000, 1)) }
        return
    }
    let (tp, _) = try facing(FacingParameters(pattern: pattern), sheet: Vec2(100_000, 1))
    #expect(tp.moves.count < 200)
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
    // A custom list is not capped by the pass helper.
    fails { $0.depth.customPasses = (1...10_001).map { Double($0) * 1e-5 }; $0.depth.cutDepth = 1 }
    // Finite depths whose span overflows.
    fails { $0.depth.startDepth = -1e308; $0.depth.cutDepth = 1e308 }
    fails { $0.depth.passDepth = 0 }
    // The selected vectors give the area; none selected gives none.
    fails({ $0.area = .vectors })
    // A tiny stepover is a typo, not a request for a million passes.
    fails { $0.stepover = 1e-9 }
    // Vectors with no finite extent give no area.
    fails({ $0.area = .vectors }, paths: [F.rect(0, 0, .infinity, 1)])
    fails({ $0.area = .vectors }, paths: [F.rect(0, 0, .nan, 1)])
    // Far from the origin a lead of a tool radius rounds away: the cutter would go down on the area's edge.
    for pattern in [FacingPattern.rasterX, .rasterY, .spiral] { fails({ $0.area = .vectors; $0.pattern = pattern }, paths: [F.rect(1e16, 1e16, 6, 4)]) }
    // Finite edges whose span overflows.
    let wide = ShapeFactory.rectangle(Rect2(min: Vec2(-1e308, 0), max: Vec2(1e308, 1)))
    for pattern in [FacingPattern.rasterX, .rasterY, .spiral] { fails({ $0.area = .vectors; $0.pattern = pattern }, paths: [wide]) }
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

@Test func ops2DFacingLeadClearanceIsAFullRadiusOnOneSideNotACornerGraze() {
    let box = Rect2(x: 0, y: 0, width: 6, height: 4)
    let r = 0.25, tol = 0.0005
    // A radius clear on one side is clear, however near the other axis it is.
    #expect(FacingOperation.isClear(Vec2(-0.25, 2), of: box, toolRadius: r, tolerance: tol))
    #expect(FacingOperation.isClear(Vec2(-0.25, -0.2), of: box, toolRadius: r, tolerance: tol))
    #expect(FacingOperation.isClear(Vec2(3, 4.25), of: box, toolRadius: r, tolerance: tol))
    // 0.2 outside on both axes is 0.283 from the corner, but only 0.2 from each edge: not accepted (the test is the grown
    // square, never looser than the round cutter), nor is a point inside.
    #expect(!FacingOperation.isClear(Vec2(-0.2, -0.2), of: box, toolRadius: r, tolerance: tol))
    #expect(!FacingOperation.isClear(Vec2(-0.2, 2), of: box, toolRadius: r, tolerance: tol))
    #expect(!FacingOperation.isClear(Vec2(3, 2), of: box, toolRadius: r, tolerance: tol))
}

@Test(arguments: [0.95, 0.85, 0.7, 0.5])
func ops2DFacingSpiralLeavesNoCoreAtAnyStepover(stepover: Double) throws {
    // Sizes whose last ring is anywhere from nothing to nearly two steps wide, square and long: the interval where the rings
    // alone leave a core wider than the cutter (between a diameter and two steps) is swept at every stepover.
    var sizes: [Vec2] = []
    var w = 0.8
    while w <= 4.2 { sizes.append(Vec2(w, w)); sizes.append(Vec2(w, 2.6)); w += 0.11 }
    for size in sizes {
        let box = Rect2(x: 0.5, y: 0.5, width: size.x, height: size.y)
        var p = FacingParameters(area: .vectors, pattern: .spiral)
        p.stepover = stepover
        let (tp, ctx) = try facing(p, paths: [F.rect(box.min.x, box.min.y, size.x, size.y)], sheet: Vec2(8, 6))
        let gap = worstGap(cuts(tp, at: 0.0625, coords: ctx.coords), over: box, grid: 0.1)
        #expect(gap <= F.bigEndMill.radius + 1e-6, "stepover \(stepover), \(size.x) x \(size.y): an uncut spot \(gap) from the path")
        // Above the cap the rings are held at it, and the program says so.
        #expect((tp.metadata["warning"]?.contains("rings") == true) == (stepover > FacingOperation.maxSpiralStepover))
    }
}

@Test func ops2DFacingLaterLayersGoDownWhereThePreviousLayerCut() throws {
    // Each layer repeats the pattern from the same lead-in point, so the column there is cut to the previous floor and the
    // rapid down may stop a gap above it. That holds beside an area inside the stock too.
    var p = FacingParameters(area: .vectors, pattern: .rasterX, depth: DepthSettings(cutDepth: 0.5))
    p.overhang = nil
    let (tp, ctx) = try facing(p, paths: [F.rect(1, 1, 3, 2)])
    let gap = 0.05   // the plunge gap the job's default gives
    var visited: [(Vec2, Double)] = []
    var cur: Vec3?
    var rapidsDown = 0
    for m in tp.moves {
        if case .rapid(let q) = m, let c = cur, q.xy.distance(to: c.xy) < 1e-9, q.z < c.z - 1e-9, q.z < ctx.coords.safeZ - 1e-9 {
            // A rapid down from safe Z stops above the top on the first layer (nothing to credit); on a later one the column
            // was cut at least to a gap below where it stops.
            let stops = ctx.coords.depth(ofMachineZ: q.z)
            if stops < 0 { continue }
            rapidsDown += 1
            #expect(visited.contains { $0.0.distance(to: q.xy) < 1e-9 && $0.1 >= stops + gap - 1e-9 },
                    "rapid down at \(q.xy) to depth \(stops) over uncut stock")
        }
        if let t = m.target {
            if case .linear = m { visited.append((t.xy, ctx.coords.depth(ofMachineZ: t.z))) }
            cur = t
        }
    }
    // Two later layers (0.5 in at a 0.2 in stepdown is three).
    #expect(rapidsDown == 2)
}

@Test func ops2DFacingWarnsWhenTheToolIsNotAFlatEndMill() throws {
    let (flat, _) = try facing(FacingParameters())
    #expect(flat.metadata["warning"] == nil)
    let ball = try #require(ToolLibrary.seeded.tools.first { $0.kind == .ballNose })
    let (tp, _) = try facing(FacingParameters(), tool: ball)
    #expect(tp.metadata["warning"]?.contains("ball nose bit is not a flat cutter") == true)
}

@Test func ops2DFacingIgnoresCustomPassesThatAreNotNumbers() throws {
    // The pass helper keeps only values strictly between the start and cut depth, which no infinity or NaN is.
    var p = FacingParameters(depth: DepthSettings(cutDepth: 0.3))
    p.depth.customPasses = [.infinity, -.infinity, .nan, 0.1]
    let (tp, ctx) = try facing(p)
    let z = F.densePoints(tp.moves).map { ctx.coords.depth(ofMachineZ: $0.z) }
    #expect(z.allSatisfy { $0.isFinite })
    #expect(Set(z.map { ($0 * 1e6).rounded() }.filter { $0 > 1 }) == [100_000, 300_000])
}
