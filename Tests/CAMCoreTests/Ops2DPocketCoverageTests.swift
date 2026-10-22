import CADCore
import Foundation
import Testing
@testable import CAMCore

/// Pocket coverage: sweep the tool footprint along the cutting moves and measure the floor area the
/// tool could have reached but did not touch. The reachable area is what a round tool of the pocket's
/// radius can cut at all: the region shrunk by the tool radius and grown back (a morphological opening),
/// so the unreachable sliver in a sharp inside corner is not counted. A point counts as uncut when it is
/// farther than the radius plus `PocketPlanner.coverageSlackFraction` of the diameter from every cut.

private let diameter = 0.25

extension SplitMix64 {
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * next() }
}

/// A star-shaped polygon: radii drawn at evenly spaced angles, so it has reflex corners and acute wedges
/// but never crosses itself.
private func starShape(_ rng: inout SplitMix64, center: Vec2, minRadius: Double, maxRadius: Double, vertices: Int) -> Path {
    var pts: [Vec2] = []
    for i in 0..<vertices {
        let a = 2 * Double.pi * (Double(i) + rng.uniform(-0.2, 0.2)) / Double(vertices)
        let r = rng.uniform(minRadius, maxRadius)
        pts.append(center + Vec2(cos(a), sin(a)) * r)
    }
    return Path(points: pts, closed: true)
}

/// A sharp triangle with its apex at `origin`.
private func wedge(origin: Vec2, length: Double, halfAngleDegrees: Double) -> Path {
    let h = halfAngleDegrees * .pi / 180
    return Path(points: [origin, origin + Vec2(cos(h), sin(h)) * length, origin + Vec2(cos(-h), sin(-h)) * length], closed: true)
}

private struct Case {
    var name: String
    var outer: Path
    var islands: [Path] = []
}

private func inside(_ loops: [[Vec2]], _ p: Vec2) -> Bool {
    loops.reduce(0) { $0 + (Polygon2D.contains($1, p) ? 1 : 0) } % 2 == 1
}

/// Segments bucketed on a grid, for nearest-cut queries.
private struct Sweep {
    var segments: [(Vec2, Vec2)]
    let cell: Double
    var buckets: [Int64: [Int]] = [:]

    init(_ segments: [(Vec2, Vec2)], cell: Double) {
        self.segments = segments; self.cell = cell
        for (i, s) in segments.enumerated() {
            let lo = Vec2(min(s.0.x, s.1.x), min(s.0.y, s.1.y)), hi = Vec2(max(s.0.x, s.1.x), max(s.0.y, s.1.y))
            for ix in Int(floor(lo.x / cell))...Int(floor(hi.x / cell)) {
                for iy in Int(floor(lo.y / cell))...Int(floor(hi.y / cell)) {
                    buckets[Self.key(ix, iy), default: []].append(i)
                }
            }
        }
    }

    static func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) &* 1_000_003 &+ Int64(y) }

    /// Distance from `p` to the nearest segment within `limit` of it; infinity when there is none.
    func distance(from p: Vec2, limit: Double) -> Double {
        var best = Double.infinity
        let span = Int(ceil(limit / cell))
        let cx = Int(floor(p.x / cell)), cy = Int(floor(p.y / cell))
        for ix in (cx - span)...(cx + span) {
            for iy in (cy - span)...(cy + span) {
                for i in buckets[Self.key(ix, iy)] ?? [] {
                    best = min(best, Polygon2D.closestPoint(onSegment: segments[i].0, segments[i].1, to: p).point.distance(to: p))
                }
            }
        }
        return best
    }
}

/// Cut segments (machine XY, which is material XY for a lower-left origin) at exactly machine z.
private func cutSegments(_ tp: Toolpath, z: Double) -> [(Vec2, Vec2)] {
    var out: [(Vec2, Vec2)] = []
    let pts = Ops2DFixture.densePoints(tp.moves, includeRapids: true)
    for (a, b) in zip(pts, pts.dropFirst()) where abs(a.z - z) < 1e-9 && abs(b.z - z) < 1e-9 && a.xy.distance(to: b.xy) > 1e-12 {
        out.append((a.xy, b.xy))
    }
    return out
}

private let cutDepth = 0.1

/// The pocket of `c` as the operation generates it, with the context and the operation.
private func program(_ c: Case, stepoverFraction: Double, strategy: PocketStrategy, allowance: Double = 0,
                     zZero: ZZeroMode = .materialTop) throws -> (tp: Toolpath, ctx: CAMContext, op: PocketOperation) {
    let tool = Tool(name: "EM", kind: .endMill, diameter: diameter, flutes: 2, stepdown: 0.2,
                    stepover: diameter * stepoverFraction, feedRate: 100, plungeRate: 30)
    var doc = Document()
    doc.job.zZero = zZero
    var ids: [UUID] = []
    for p in [c.outer] + c.islands {
        let s = Shape(layerID: doc.defaultLayerID, paths: [p])
        doc.add(s)
        ids.append(s.id)
    }
    let ctx = CAMContext(document: doc, tools: ToolLibrary(tools: [tool]))
    let params = PocketParameters(depth: DepthSettings(cutDepth: cutDepth), strategy: strategy, allowance: allowance)
    let op = PocketOperation(setup: OperationSetup(name: "Pocket", toolID: tool.id, shapeIDs: ids), params: params)
    return (try #require(try op.generate(in: ctx).last), ctx, op)
}

private struct CoverageResult {
    var uncutArea: Double
    var worstDistance: Double
}

/// `gridDivisor` points per tool radius, for the sampling of the reachable floor.
private func coverage(_ c: Case, stepoverFraction: Double, strategy: PocketStrategy, allowance: Double = 0,
                      gridDivisor: Double = 6) throws -> CoverageResult {
    let (tp, ctx, op) = try program(c, stepoverFraction: stepoverFraction, strategy: strategy, allowance: allowance)
    let r = diameter / 2
    let tol = ctx.tolerance
    let loops = ShapeGeometry.loops(of: ctx.shapes(for: op.setup), tolerance: tol).closed
    let region = Polygon2D.region(fromLoops: loops)
    let shrunk = GeomKernel.offset(region, by: -(r + allowance), join: .round, arcTolerance: tol)
    let reachable = GeomKernel.offset(shrunk, by: r, join: .round, arcTolerance: tol)

    let sweep = Sweep(cutSegments(tp, z: ctx.coords.z(depth: cutDepth)), cell: r)
    let b = Rect2(points: reachable.flatMap { $0 })
    let h = r / gridDivisor
    // The planner leaves up to the slack; the tool-centre outline is an arc-flattened polygon, so allow
    // a couple of tolerances more.
    let limit = r + diameter * PocketPlanner.coverageSlackFraction + 2 * tol
    var uncut = 0
    var worst = 0.0
    var y = b.min.y + h / 2
    while y < b.max.y {
        var x = b.min.x + h / 2
        while x < b.max.x {
            let p = Vec2(x, y)
            if inside(reachable, p) {
                let d = sweep.distance(from: p, limit: r + 4 * tol)
                if d > limit {
                    uncut += 1
                    worst = max(worst, d - r)
                }
            }
            x += h
        }
        y += h
    }
    return CoverageResult(uncutArea: Double(uncut) * h * h, worstDistance: worst)
}

private func cases(count: Int, seed: UInt64, withIslands: Bool) -> [Case] {
    var rng = SplitMix64(seed: seed)
    var out: [Case] = []
    for i in 0..<count {
        let center = Vec2(3, 3)
        switch i % 3 {
        case 0:
            let vertices = Int(rng.uniform(5, 11))
            var c = Case(name: "star \(i)", outer: starShape(&rng, center: center, minRadius: 0.5, maxRadius: 1.6, vertices: vertices))
            if withIslands {
                c.islands = [ShapeFactory.rectangle(Rect2(x: 2.85, y: 2.85, width: rng.uniform(0.1, 0.3), height: rng.uniform(0.1, 0.3)))]
            }
            out.append(c)
        case 1:
            var c = Case(name: "wedge \(i)", outer: wedge(origin: Vec2(1, 3), length: rng.uniform(2, 3.5), halfAngleDegrees: rng.uniform(8, 35)))
            if withIslands {
                c.islands = [ShapeFactory.circle(center: Vec2(2.6, 3), radius: rng.uniform(0.05, 0.12))]
            }
            out.append(c)
        default:
            let w = rng.uniform(0.6, 3), h = rng.uniform(0.6, 3)
            var c = Case(name: "rect \(i)", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: w, height: h)))
            if withIslands {
                c.islands = [ShapeFactory.rectangle(Rect2(x: 1.3, y: 1.3, width: rng.uniform(0.1, 0.25), height: rng.uniform(0.1, 0.25)))]
            }
            out.append(c)
        }
    }
    return out
}

private func expectCovered(_ c: Case, fraction: Double, strategy: PocketStrategy, allowance: Double = 0, gridDivisor: Double = 6,
                           comment: String) throws {
    let r = try coverage(c, stepoverFraction: fraction, strategy: strategy, allowance: allowance, gridDivisor: gridDivisor)
    #expect(r.uncutArea == 0, Comment(rawValue: "\(comment): \(c.name) leaves \(r.uncutArea) sq in uncut, up to \(r.worstDistance) in beyond the tool's reach"))
}

@Test(arguments: [0.5, 0.8, 0.9, 1.0])
func ops2DPocketOffsetCoversEverythingTheToolCanReach(fraction: Double) throws {
    for islands in [false, true] {
        for c in cases(count: 6, seed: 7, withIslands: islands) {
            try expectCovered(c, fraction: fraction, strategy: .offset, comment: "offset \(Int(fraction * 100))%")
        }
    }
}

@Test(arguments: [0.9, 1.0])
func ops2DPocketOffsetCoversWithAnAllowance(fraction: Double) throws {
    for c in cases(count: 3, seed: 5, withIslands: true) {
        try expectCovered(c, fraction: fraction, strategy: .offset, allowance: 0.02, comment: "offset \(Int(fraction * 100))% with allowance")
    }
}

@Test(arguments: [0.5, 1.0], [0.0, 35.0])
func ops2DPocketRasterWithAProfilePassCoversEverythingTheToolCanReach(fraction: Double, angle: Double) throws {
    for islands in [false, true] {
        for c in cases(count: 4, seed: 11, withIslands: islands) {
            try expectCovered(c, fraction: fraction, strategy: .raster(angle: angle, profilePass: true),
                              comment: "raster \(Int(angle))° \(Int(fraction * 100))%")
        }
    }
}

/// Sampling is a sixth of a radius; the scallop at a square corner is a few thousandths wide, so look at
/// it with a much finer grid on a pocket that is only corners.
@Test(arguments: [0.9, 0.95, 1.0])
func ops2DPocketCoversTheScallopAtASquareCorner(fraction: Double) throws {
    let square = Case(name: "square", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 0.9, height: 0.9)))
    try expectCovered(square, fraction: fraction, strategy: .offset, gridDivisor: 40, comment: "offset \(Int(fraction * 100))%")
}

/// The tracker cases: a wide pocket a little more than two tools across (a stud left in the middle), a
/// hole 1.1 tool diameters across, a channel 1.1 diameters wide, the sharpest wedge, and islands.
private func trackerCases() -> [Case] {
    let d = diameter
    return [
        Case(name: "8 mm pocket, 3 mm bit", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: d * 8 / 3, height: 1.5))),
        Case(name: "round hole 1.1 D", outer: ShapeFactory.circle(center: Vec2(2, 2), radius: 0.55 * d)),
        Case(name: "square hole 1.1 D", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 1.1 * d, height: 1.1 * d))),
        Case(name: "channel 1.1 D", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 1.1 * d, height: 2))),
        Case(name: "8 degree wedge", outer: wedge(origin: Vec2(1, 3), length: 3, halfAngleDegrees: 8)),
        Case(name: "square with a square island", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 2, height: 2)),
             islands: [ShapeFactory.rectangle(Rect2(x: 1.9, y: 1.9, width: 0.2, height: 0.2))]),
        // A ring 1.1 diameters wide around an island: a 2 in square with a round island that leaves 1.1 D to the walls.
        Case(name: "ring 1.1 D around an island", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 2, height: 2)),
             islands: [ShapeFactory.circle(center: Vec2(2, 2), radius: 1 - 1.1 * d)]),
    ]
}

@Test(arguments: [0.5, 0.8, 0.9, 1.0])
func ops2DPocketCoversTheTrackerCases(fraction: Double) throws {
    for c in trackerCases() {
        try expectCovered(c, fraction: fraction, strategy: .offset, comment: "offset \(Int(fraction * 100))%")
        try expectCovered(c, fraction: fraction, strategy: .raster(angle: 0, profilePass: true), comment: "raster \(Int(fraction * 100))%")
    }
}

@Test func ops2DPocketReachesAHoleJustLargerThanTheTool() throws {
    // A circle 1.1 tool diameters across: the centre can move only 0.05 diameters, but the pocket is
    // not empty and not reported too small.
    let hole = Case(name: "round hole 1.1 D", outer: ShapeFactory.circle(center: Vec2(2, 2), radius: 0.55 * diameter))
    let (tp, ctx, _) = try program(hole, stepoverFraction: 0.4, strategy: .offset)
    #expect(tp.metadata["warning"] == nil)
    #expect(!cutSegments(tp, z: ctx.coords.z(depth: cutDepth)).isEmpty)
}

/// The extra cuts are real G-code: they follow the conventions in both Z-zero modes and stay a tool
/// radius from the walls.
@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DPocketCleanupCutsStayInsideAndFollowTheConventions(mode: ZZeroMode) throws {
    for c in trackerCases() + cases(count: 3, seed: 5, withIslands: true) {
        let (tp, ctx, op) = try program(c, stepoverFraction: 0.95, strategy: .offset, zZero: mode)
        #expect(Ops2DFixture.conventionViolations(tp, coords: ctx.coords).isEmpty, Comment(rawValue: c.name))
        #expect(tp.metadata["warning"] == nil, Comment(rawValue: "\(c.name): \(tp.metadata["warning"] ?? "")"))
        let tol = ctx.tolerance
        let loops = ShapeGeometry.loops(of: ctx.shapes(for: op.setup), tolerance: tol).closed
        let region = Polygon2D.region(fromLoops: loops)
        for p in Ops2DFixture.densePoints(tp.moves) where p.z < ctx.coords.materialTopZ - 1e-9 {
            let q = ctx.coords.materialXY(fromMachine: p.xy)
            #expect(inside(region, q), Comment(rawValue: "\(c.name): cut point \(q) outside the pocket"))
            let wall = region.map { Polygon2D.distance(from: q, toLoop: $0) }.min() ?? 0
            #expect(wall >= diameter / 2 - 4 * tol, Comment(rawValue: "\(c.name): cut point \(q) is \(wall) from a wall"))
        }
    }
}

/// One halving covers a stepover under the diameter. The operation never asks for more (it clamps the
/// stepover to 95% of the diameter), but a planner given a stepover of 3 diameters cannot be covered by
/// it, and says so: the area it reports is what makes the operation warn and keep a clearance tool from
/// handing over.
@Test func ops2DPocketPlannerReportsFloorItCouldNotCover() {
    let square = Polygon2D.region(fromLoops: [ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 2, height: 2)).flattened()])
    func report(stepover: Double) -> Double {
        PocketPlanner(region: square, toolRadius: diameter / 2, stepover: stepover, allowance: 0, tolerance: 0.0005,
                      direction: .climb).offsetClearingReport(from: Vec2(0, 0)).uncoveredArea
    }
    #expect(report(stepover: diameter * 0.95) == 0)
    #expect(report(stepover: diameter * 3) > 0.001)
}
