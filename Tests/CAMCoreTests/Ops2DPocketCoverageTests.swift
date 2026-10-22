import CADCore
import Foundation
import Testing
@testable import CAMCore

/// Pocket coverage: sweep the tool footprint along the cutting moves and measure the floor area the
/// tool could have reached but did not touch. The reachable area is what a round tool of the pocket's
/// radius can cut at all: the region shrunk by the tool radius and grown back (a morphological opening),
/// so the unreachable sliver in a sharp inside corner is not counted.

private struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * Double(next() >> 11) / Double(1 << 53)
    }
}

/// A star-shaped polygon: radii drawn at evenly spaced angles, so it has reflex corners and acute wedges
/// but never crosses itself.
private func starShape(_ rng: inout SplitMix, center: Vec2, minRadius: Double, maxRadius: Double, vertices: Int) -> Path {
    var pts: [Vec2] = []
    for i in 0..<vertices {
        let a = 2 * Double.pi * (Double(i) + rng.uniform(-0.2, 0.2)) / Double(vertices)
        let r = rng.uniform(minRadius, maxRadius)
        pts.append(center + Vec2(cos(a), sin(a)) * r)
    }
    return Path(points: pts, closed: true)
}

/// A sharp triangle (acute at one corner).
private func wedge(_ rng: inout SplitMix, origin: Vec2, length: Double, halfAngleDegrees: Double) -> Path {
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

    /// Distance from `p` to the nearest segment within `limit` of it, or `limit` + something when none.
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

private struct CoverageResult {
    var uncutArea: Double
    var worstDistance: Double
    var reachableArea: Double
    var warning: String?
}

private func coverage(_ c: Case, stepoverFraction: Double, strategy: PocketStrategy, allowance: Double = 0,
                      diameter: Double = 0.25) throws -> CoverageResult {
    let tool = Tool(name: "EM", kind: .endMill, diameter: diameter, flutes: 2, stepdown: 0.2,
                    stepover: diameter * stepoverFraction, feedRate: 100, plungeRate: 30)
    var doc = Document()
    var ids: [UUID] = []
    for p in [c.outer] + c.islands {
        let s = Shape(layerID: doc.defaultLayerID, paths: [p])
        doc.add(s)
        ids.append(s.id)
    }
    let ctx = CAMContext(document: doc, tools: ToolLibrary(tools: [tool]))
    var params = PocketParameters(depth: DepthSettings(cutDepth: 0.1), strategy: strategy, allowance: allowance)
    params.ramp = RampSettings()
    let op = PocketOperation(setup: OperationSetup(name: "Pocket", toolID: tool.id, shapeIDs: ids), params: params)
    let tps = try op.generate(in: ctx)
    let tp = try #require(tps.last)
    let r = diameter / 2
    let tol = ctx.tolerance

    let loops = ShapeGeometry.loops(of: ctx.shapes(for: op.setup), tolerance: tol).closed
    let region = Polygon2D.region(fromLoops: loops)
    let shrunk = GeomKernel.offset(region, by: -(r + allowance), join: .round, arcTolerance: tol)
    let reachable = GeomKernel.offset(shrunk, by: r, join: .round, arcTolerance: tol)

    let segs = cutSegments(tp, z: ctx.coords.z(depth: 0.1))
    let sweep = Sweep(segs, cell: r)
    let b = Rect2(points: reachable.flatMap { $0 })
    let h = r / 6
    var uncut = 0, reach = 0
    var worst = 0.0
    var y = b.min.y + h / 2
    while y < b.max.y {
        var x = b.min.x + h / 2
        while x < b.max.x {
            let p = Vec2(x, y)
            if inside(reachable, p) {
                reach += 1
                let d = sweep.distance(from: p, limit: r + 4 * tol)
                // The planner leaves up to 2% of the diameter (`PocketPlanner.coverageSlack`); the tool-centre
                // outline is an arc-flattened polygon, so allow a couple of tolerances more.
                if d > r + diameter * 0.02 + 2 * tol {
                    uncut += 1
                    worst = max(worst, d - r)
                }
            }
            x += h
        }
        y += h
    }
    return CoverageResult(uncutArea: Double(uncut) * h * h, worstDistance: worst, reachableArea: Double(reach) * h * h,
                          warning: tp.metadata["warning"])
}

private func cases(count: Int, seed: UInt64, withIslands: Bool) -> [Case] {
    var rng = SplitMix(state: seed)
    var out: [Case] = []
    for i in 0..<count {
        let center = Vec2(3, 3)
        switch i % 3 {
        case 0:
            var c = Case(name: "star \(i)", outer: starShape(&rng, center: center, minRadius: 0.5, maxRadius: 1.6, vertices: Int(rng.uniform(5, 11))))
            if withIslands {
                c.islands = [ShapeFactory.rectangle(Rect2(x: 2.85, y: 2.85, width: rng.uniform(0.1, 0.3), height: rng.uniform(0.1, 0.3)))]
            }
            out.append(c)
        case 1:
            var c = Case(name: "wedge \(i)", outer: wedge(&rng, origin: Vec2(1, 3), length: rng.uniform(2, 3.5), halfAngleDegrees: rng.uniform(8, 35)))
            if withIslands {
                c.islands = [ShapeFactory.circle(center: Vec2(2.6, 3), radius: rng.uniform(0.05, 0.12))]
            }
            out.append(c)
        default:
            var c = Case(name: "rect \(i)", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: rng.uniform(0.6, 3), height: rng.uniform(0.6, 3))))
            if withIslands {
                c.islands = [ShapeFactory.rectangle(Rect2(x: 1.3, y: 1.3, width: rng.uniform(0.1, 0.25), height: rng.uniform(0.1, 0.25)))]
            }
            out.append(c)
        }
    }
    return out
}


private func expectCovered(_ c: Case, fraction: Double, strategy: PocketStrategy, comment: String) throws {
    let r = try coverage(c, stepoverFraction: fraction, strategy: strategy)
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

@Test(arguments: [0.5, 1.0], [0.0, 35.0])
func ops2DPocketRasterWithAProfilePassCoversEverythingTheToolCanReach(fraction: Double, angle: Double) throws {
    for islands in [false, true] {
        for c in cases(count: 4, seed: 11, withIslands: islands) {
            try expectCovered(c, fraction: fraction, strategy: .raster(angle: angle, profilePass: true),
                              comment: "raster \(Int(angle))° \(Int(fraction * 100))%")
        }
    }
}

/// The tracker cases: a wide pocket a little more than two tools across (a stud left in the middle), a
/// hole 1.1 tool diameters across, a channel 1.1 diameters wide, and the sharpest wedges.
private func trackerCases() -> [Case] {
    let d = 0.25
    var rng = SplitMix(state: 3)
    return [
        Case(name: "8 mm pocket, 3 mm bit", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: d * 8 / 3, height: 1.5))),
        Case(name: "round hole 1.1 D", outer: ShapeFactory.circle(center: Vec2(2, 2), radius: 0.55 * d)),
        Case(name: "square hole 1.1 D", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 1.1 * d, height: 1.1 * d))),
        Case(name: "channel 1.1 D", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 1.1 * d, height: 2))),
        Case(name: "8 degree wedge", outer: wedge(&rng, origin: Vec2(1, 3), length: 3, halfAngleDegrees: 8)),
        Case(name: "square with a square island", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 2, height: 2)),
             islands: [ShapeFactory.rectangle(Rect2(x: 1.9, y: 1.9, width: 0.2, height: 0.2))]),
        Case(name: "hole 1.1 D around an island", outer: ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 1.6, height: 1.6)),
             islands: [ShapeFactory.circle(center: Vec2(1.8, 1.8), radius: 0.55 * d + 0.55 * d)]),
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
    let hole = Case(name: "round hole 1.1 D", outer: ShapeFactory.circle(center: Vec2(2, 2), radius: 0.55 * 0.25))
    let tool = Tool(name: "EM", kind: .endMill, diameter: 0.25, flutes: 2, stepdown: 0.2, stepover: 0.1, feedRate: 100, plungeRate: 30)
    var doc = Document()
    let s = Shape(layerID: doc.defaultLayerID, paths: [hole.outer])
    doc.add(s)
    let ctx = CAMContext(document: doc, tools: ToolLibrary(tools: [tool]))
    let op = PocketOperation(setup: OperationSetup(name: "Pocket", toolID: tool.id, shapeIDs: [s.id]),
                             params: PocketParameters(depth: DepthSettings(cutDepth: 0.1)))
    let tps = try op.generate(in: ctx)
    #expect(tps.count == 1)
    #expect(tps[0].metadata["warning"] == nil)
    #expect(!cutSegments(tps[0], z: ctx.coords.z(depth: 0.1)).isEmpty)
}
