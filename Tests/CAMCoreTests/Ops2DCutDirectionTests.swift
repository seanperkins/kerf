import CADCore
import Foundation
import Testing
@testable import CAMCore

// Cut direction is a safety property: a climb cut on a clockwise spindle keeps the material on the
// right of travel, so a loop that comes out wound the other way tears the edge out of plywood.
// These tests read the emitted toolpath back, split it into the laps it cuts, and read each lap's
// direction from its geometry alone, over every option that could reverse a loop on the way out:
// side, corner style, leads, last-pass reverse, ramps, tabs, ordering, start points, islands,
// raster walls and rest machining. The pocket planner's chains, open rest-machining pieces
// included, are checked the same way.

private typealias F = Ops2DFixture

/// Nearest point on any source vector to `p`, with its distance and the vector's index.
private func nearest(_ p: Vec2, in sources: [[Vec2]]) -> (point: Vec2, distance: Double, loop: Int) {
    var best = (point: p, distance: Double.infinity, loop: 0)
    for (k, src) in sources.enumerated() {
        for i in 0..<src.count {
            let c = Polygon2D.closestPoint(onSegment: src[i], src[(i + 1) % src.count], to: p).point
            let d = c.distance(to: p)
            if d < best.distance { best = (c, d, k) }
        }
    }
    return best
}

/// The direction a cut runs relative to the material, read from its geometry alone. An offset cut
/// runs the tool radius away from its vector with the material on the vector's side, so the sign
/// of Σ cross(travel, toward the nearest vector) over the segments says which side the material
/// is on: negative is the right of travel, which is climb on a clockwise spindle. The legs of a
/// zig-zag ramp cancel. A cut on the line (`onLine`) has no offset, so there the material is on
/// whichever side the vectors' region lies. Also returns the cut's offset from the vectors and
/// the vector it follows. The direction is nil when the geometry cannot tell (no net side).
private func observed(_ pts: [Vec2], closed: Bool, sources: [[Vec2]], onLine: Bool = false)
    -> (direction: CutDirection?, distance: Double, loop: Int) {
    var sum = 0.0, dist = Double.infinity, loop = 0
    let n = closed ? pts.count : pts.count - 1
    for i in 0..<n {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        let t = b - a
        guard t.length > 1e-9 else { continue }
        let m = (a + b) * 0.5
        let (q, d, k) = nearest(m, in: sources)
        if d < dist { dist = d; loop = k }
        let u: Vec2
        if onLine {
            let left = t.perpendicular.normalized
            u = Polygon2D.regionContains(sources, m + left * 1e-3) ? left : -left
        } else {
            u = (q - m) * (1 / max(d, 1e-9))
        }
        sum += t.cross(u)
    }
    let direction: CutDirection? = sum < -1e-9 ? .climb : (sum > 1e-9 ? .conventional : nil)
    return (direction, dist, loop)
}

/// True when `pts` keeps one distance from the vectors all the way along (a mitred corner reaches
/// √2 of it): an offset loop or a piece of one, not a figure a raster and its links happen to draw.
private func isOffsetPath(_ pts: [Vec2], closed: Bool, sources: [[Vec2]]) -> Bool {
    var ds: [Double] = []
    let n = closed ? pts.count : pts.count - 1
    for i in 0..<n {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        for k in 0..<8 { ds.append(nearest(a + (b - a) * (Double(k) / 8), in: sources).distance) }
    }
    guard let lo = ds.min(), let hi = ds.max() else { return false }
    return hi <= lo * 1.5 + 2e-3
}

/// The cutting moves of `tp` between rapids, as dense material-frame points (arcs sampled).
private func runs(of tp: Toolpath, coords: MachineCoordinates) -> [[Vec2]] {
    var runs: [[Vec2]] = []
    var pending: [Move] = []
    func flush() {
        let pts = F.densePoints(pending).map { coords.materialXY(fromMachine: $0.xy) }
        if pts.count > 1 { runs.append(pts) }
    }
    for m in tp.moves {
        if case .rapid = m {
            flush()
            pending = [m]   // seeds the next run's start position; densePoints leaves rapids out
        } else {
            pending.append(m)
        }
    }
    flush()
    return runs
}

/// Closed laps of `tp` in the material frame: the offset loops it cuts, one per circuit. Within each
/// run of cutting moves between rapids, a lap starts at a point and ends the first time the path
/// comes back through that point enclosing real area and running parallel to a source vector all
/// the way round. A zig-zag ramp's retrace, a lead or a link never closes one; a lap traced twice
/// (spiral ramp) or cut again without a retract gives one lap per circuit; a raster line that ends
/// on a wall closes nothing, because the figure it would close is not parallel to a wall, so the
/// search moves on and finds the wall's own lap from its own start. The path may merely pass
/// through a closing point, since the builder merges collinear points.
private func laps(of tp: Toolpath, coords: MachineCoordinates, sources: [[Vec2]]) -> [[Vec2]] {
    var out: [[Vec2]] = []
    for run in runs(of: tp, coords: coords) {
        var i = 0
        while i < run.count - 2 {
            let start = run[i]
            var closed = false
            var j = i + 2
            while j < run.count - 1 {
                // Arcs are sampled 16 to a sweep, so a lap that starts on one closes within the chord sag.
                let hit = Polygon2D.closestPoint(onSegment: run[j], run[j + 1], to: start).point
                if hit.distance(to: start) <= 2e-3 {
                    var lap = Array(run[i...j]) + [start]
                    // A linear lead in and out of the same point retraces one spur: drop it from both
                    // ends so the lap is the loop itself.
                    while lap.count > 4, lap[1].distance(to: lap[lap.count - 2]) <= 2e-3 {
                        lap.removeFirst(); lap.removeLast()
                    }
                    if abs(Polygon2D.signedArea(lap)) > 0.02, isOffsetPath(lap, closed: true, sources: sources) {
                        out.append(lap)
                        i = j + 1
                        closed = true
                        break
                    }
                }
                j += 1
            }
            if !closed { i += 1 }
        }
    }
    return out
}

private func sourceLoops(_ paths: [Path], tolerance: Double) -> [[Vec2]] {
    Polygon2D.region(fromLoops: paths.map { $0.flattened(tolerance: tolerance) })
}

private let cutDepth = DepthSettings(cutDepth: 0.3)
private let ramps: [RampType?] = [nil, .zigzag, .spiral, .smooth]

// MARK: Profiles

private struct ProfileCase: CustomStringConvertible {
    var side: ProfileSide
    var direction: CutDirection
    var sharp = false
    var lead = LeadType.none
    var lastPass: ProfileLastPass?
    var ramp: RampType?
    var tabs = false
    var order = ProfileOrder.nearest
    var start = ProfileStartPoint.nearest

    var description: String {
        "\(side)/\(direction) sharp=\(sharp) lead=\(lead) lastPass=\(lastPass.map { $0.reverseDirection ? "reversed" : "same" } ?? "none") "
            + "ramp=\(ramp.map { "\($0)" } ?? "off") tabs=\(tabs) order=\(order) start=\(start)"
    }

    static let lastPassAllowance = 0.06
    static let lastPasses: [ProfileLastPass?] = [nil, ProfileLastPass(allowance: lastPassAllowance, reverseDirection: false),
                                                 ProfileLastPass(allowance: lastPassAllowance, reverseDirection: true)]

    /// The last pass the generator will honour: a cut on the line has no allowance to take off.
    var effectiveLastPass: ProfileLastPass? { side == .on ? nil : lastPass }

    var params: ProfileParameters {
        var p = ProfileParameters(depth: cutDepth, side: side, direction: direction)
        p.sharpCorners = sharp
        p.lead = LeadSettings(type: lead, distance: 0.25, overcut: lead == .arc ? 0.1 : 0)
        p.lastPass = lastPass
        if let ramp { p.ramp = RampSettings(isEnabled: true, type: ramp, length: 0.5, maxAngle: 15) }
        p.tabs = TabSettings(isEnabled: tabs, length: 0.25, thickness: 0.1, countPerPath: 2)
        p.order = order
        p.startPoint = start
        return p
    }
}

private struct ProfileFixture {
    var ctx: CAMContext
    var ids: [UUID]
    var sources: [[Vec2]]
    var passes: Int

    init(_ paths: [Path], asOneShape: Bool = false) {
        (ctx, ids) = asOneShape ? F.document(shapePaths: paths) : F.document(paths)
        sources = sourceLoops(paths, tolerance: ctx.tolerance)
        passes = cutDepth.passDepths(toolStepdown: F.endMill.stepdown).count
    }
}

/// Runs one profile and checks every lap: its direction, and that each source vector got at least
/// one lap per depth pass (plus a finishing lap when there is a last pass), so no option is ever
/// checked on zero laps.
private func checkProfile(_ c: ProfileCase, _ f: ProfileFixture, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let op = ProfileOperation(setup: OperationSetup(name: "Profile", toolID: F.endMill.id, shapeIDs: f.ids), params: c.params)
    let tps = try op.generate(in: f.ctx)
    let tp = try #require(tps.first, "\(c)", sourceLocation: sourceLocation)
    #expect(F.conventionViolations(tp, coords: f.ctx.coords).isEmpty, "\(c)", sourceLocation: sourceLocation)
    var rough = [Int](repeating: 0, count: f.sources.count), finish = rough
    for lap in laps(of: tp, coords: f.ctx.coords, sources: f.sources) {
        let (direction, d, loop) = observed(lap, closed: true, sources: f.sources, onLine: c.side == .on)
        // Roughing laps run outside the last pass's allowance; the finishing lap is at the tool radius.
        let isFinish = c.effectiveLastPass != nil && d < F.endMill.radius + ProfileCase.lastPassAllowance / 2
        if isFinish { finish[loop] += 1 } else { rough[loop] += 1 }
        let want = isFinish && c.effectiveLastPass!.reverseDirection ? c.direction.reversed : c.direction
        #expect(direction == want,
                "\(c): \(isFinish ? "finishing" : "roughing") lap along vector \(loop) near \(lap[0]) runs \(direction.map { "\($0)" } ?? "nowhere"), wanted \(want)",
                sourceLocation: sourceLocation)
    }
    for i in f.sources.indices {
        #expect(rough[i] >= f.passes, "\(c): \(rough[i]) roughing lap(s) along vector \(i), wanted \(f.passes)",
                sourceLocation: sourceLocation)
        if c.effectiveLastPass != nil {
            #expect(finish[i] >= 1, "\(c): no finishing lap along vector \(i)", sourceLocation: sourceLocation)
        }
    }
}

@Test(arguments: ProfileSide.allCases, CutDirection.allCases)
func profileLoopsKeepTheRequestedDirectionUnderEveryOption(side: ProfileSide, direction: CutDirection) throws {
    // The options that touch the loop itself, fully crossed: corner style, leads, last pass, ramp.
    let f = ProfileFixture([F.rect(1, 1, 3, 2), F.rect(5, 1, 2, 2)])
    for sharp in [false, true] {
        for lead in LeadType.allCases {
            for lastPass in ProfileCase.lastPasses {
                for ramp in ramps {
                    try checkProfile(ProfileCase(side: side, direction: direction, sharp: sharp, lead: lead,
                                                 lastPass: lastPass, ramp: ramp), f)
                }
            }
        }
    }
}

@Test(arguments: ProfileSide.allCases, CutDirection.allCases)
func profileLoopsKeepTheRequestedDirectionUnderOrderingTabsAndStartPoints(side: ProfileSide, direction: CutDirection) throws {
    // The options that reorder or rotate a loop or raise the cut over tabs, crossed with the ramps.
    // Ordering only reorders loops and a start point only rotates one, so each is varied on its own.
    let f = ProfileFixture([F.rect(1, 1, 3, 2), F.rect(5, 1, 2, 2)])
    let picks = ProfileOrder.allCases.map { ($0, ProfileStartPoint.nearest) }
        + ProfileStartPoint.allCases.map { (ProfileOrder.nearest, $0) }
    for (order, start) in picks {
        for tabs in [false, true] {
            for ramp in ramps {
                try checkProfile(ProfileCase(side: side, direction: direction, ramp: ramp, tabs: tabs,
                                             order: order, start: start), f)
            }
        }
    }
}

@Test(arguments: CutDirection.allCases)
func onTheLineNestingTellsHolesFromDuplicatesOverlapsAndNotches(direction: CutDirection) throws {
    // Telling holes apart must rest on area, not on vertices: a stacked copy, a near copy, a partly
    // overlapping vector, an abutting part, a part filling another's notch and a part bridging it
    // all keep cutting as outer loops (the part inside each, clockwise for climb), while a true hole,
    // even one touching the outer edge or under a duplicated outer, runs the other way.
    let u = Path(points: [Vec2(0, 0), Vec2(6, 0), Vec2(6, 4), Vec2(4, 4), Vec2(4, 1), Vec2(2, 1), Vec2(2, 4), Vec2(0, 4)], closed: true)
    let cases: [(label: String, paths: [Path], holes: [Bool])] = [
        ("duplicates", [F.rect(1, 1, 3, 2), F.rect(1, 1, 3, 2)], [false, false]),
        ("near duplicates", [F.rect(1, 1, 3, 2), F.rect(1, 1, 3.0004, 2)], [false, false]),
        ("overlap", [F.rect(0, 0, 6, 4), F.rect(4, 2, 4, 2)], [false, false]),
        ("abutting", [F.rect(0, 0, 2, 2), F.rect(2, 0, 2, 2)], [false, false]),
        ("notch", [u, F.rect(2, 1, 2, 3)], [false, false]),
        ("bridge", [u, F.rect(1, 3, 4, 0.5)], [false, false]),
        ("duplicated outer", [F.rect(0, 0, 6, 4), F.rect(0, 0, 6, 4), F.rect(2, 1, 2, 2)], [false, false, true]),
        ("touching hole", [F.rect(0, 0, 6, 4), F.rect(1, 0, 2, 2)], [false, true]),
    ]
    let passes = cutDepth.passDepths(toolStepdown: F.endMill.stepdown).count
    for c in cases {
        let (ctx, ids) = F.document(c.paths)
        var p = ProfileParameters(depth: cutDepth, side: .on, direction: direction)
        p.sharpCorners = true
        let tp = try #require(try ProfileOperation(setup: OperationSetup(name: "On", toolID: F.endMill.id, shapeIDs: ids),
                                                   params: p).generate(in: ctx).first)
        let raw = c.paths.map { $0.flattened(tolerance: ctx.tolerance) }   // no union: duplicates would cancel
        let found = laps(of: tp, coords: ctx.coords, sources: raw)
        #expect(found.count >= passes * c.paths.count, "\(c.label) \(direction): \(found.count) lap(s)")
        for lap in found {
            // The lap follows the vector whose extent it shares (a hole may touch the outer's edge).
            let box = Rect2(points: lap)
            let loop = raw.indices.min { a, b in
                let ba = Rect2(points: raw[a]), bb = Rect2(points: raw[b])
                return ba.min.distance(to: box.min) + ba.max.distance(to: box.max)
                    < bb.min.distance(to: box.min) + bb.max.distance(to: box.max)
            }!
            let want = (direction == .climb) == c.holes[loop] ? 1.0 : -1.0
            let area = Polygon2D.signedArea(lap)
            #expect((area < 0 ? -1.0 : 1.0) == want,
                    "\(c.label) \(direction): lap on vector \(loop) near \(lap[0]) has area \(area), wanted \(want > 0 ? "CCW" : "CW")")
        }
    }
}

@Test(arguments: CutDirection.allCases)
func prismCarvesAHoleInTheSameSenseAsTheOuterEdge(direction: CutDirection) throws {
    // A prism carve runs the V-bit's tip on the line round every loop of a region, holes included
    // (the counter of a letter): the material is the region, so both loops keep it on the same side.
    let paths = [F.rect(0, 0, 4, 3), F.rect(1, 1, 2, 1)]
    let (ctx, ids) = F.document(shapePaths: paths)
    let sources = sourceLoops(paths, tolerance: ctx.tolerance)
    let vBit = ToolLibrary.seeded.tools[6]   // 90°, 1/2 in
    let op = PrismOperation(setup: OperationSetup(name: "Prism", toolID: vBit.id, shapeIDs: ids),
                            params: PrismParameters(direction: direction))
    let tp = try #require(try op.generate(in: ctx).first)
    var perLoop = [Int](repeating: 0, count: sources.count)
    for lap in laps(of: tp, coords: ctx.coords, sources: sources) {
        let (observedDirection, _, loop) = observed(lap, closed: true, sources: sources, onLine: true)
        perLoop[loop] += 1
        #expect(observedDirection == direction, "\(direction): lap along vector \(loop) near \(lap[0]) runs \(observedDirection.map { "\($0)" } ?? "nowhere")")
    }
    #expect(perLoop.allSatisfy { $0 >= 1 }, "\(direction): laps per vector \(perLoop)")
}

@Test(arguments: ProfileSide.allCases, CutDirection.allCases)
func profileHoleLoopsRunOppositeToTheOuterLoop(side: ProfileSide, direction: CutDirection) throws {
    // A ring: the material is on the other side of the hole's loop, so it winds the other way. On
    // the line too: the part is the ring, on the left of the outer loop and the right of the hole.
    let f = ProfileFixture([F.rect(0, 0, 6, 4), F.rect(2, 1, 2, 2)], asOneShape: true)
    for lastPass in [nil, ProfileCase.lastPasses[2]] {
        for lead in LeadType.allCases {
            try checkProfile(ProfileCase(side: side, direction: direction, lead: lead, lastPass: lastPass), f)
        }
    }
}

// MARK: Pockets

private struct PocketCase: CustomStringConvertible {
    var direction: CutDirection
    var strategy: PocketStrategy
    var profileFirst = false
    var ramp: RampType?
    var clearance = false

    var description: String {
        "\(direction) \(strategy) profileFirst=\(profileFirst) ramp=\(ramp.map { "\($0)" } ?? "off") clearance=\(clearance)"
    }

    var params: PocketParameters {
        var p = PocketParameters(depth: cutDepth, strategy: strategy, direction: direction)
        p.profilePassFirst = profileFirst
        if let ramp { p.ramp = RampSettings(isEnabled: true, type: ramp, length: 0.5, maxAngle: 15) }
        if clearance { p.clearanceToolIDs = [F.bigEndMill.id] }
        return p
    }

    static func all(direction: CutDirection) -> [PocketCase] {
        var out: [PocketCase] = []
        for strategy in [PocketStrategy.offset, .raster(angle: 0, profilePass: true), .raster(angle: 45, profilePass: true)] {
            // Profile-pass-first only means something with a raster.
            for profileFirst in (strategy == .offset ? [false] : [false, true]) {
                for ramp in ramps {
                    for clearance in [false, true] {
                        out.append(PocketCase(direction: direction, strategy: strategy, profileFirst: profileFirst,
                                              ramp: ramp, clearance: clearance))
                    }
                }
            }
        }
        return out
    }
}

private let pocketPaths = [F.rect(0, 0, 6, 4), F.rect(2.25, 1.5, 1.5, 1)]

@Test(arguments: CutDirection.allCases)
func pocketWallsAndIslandWallsKeepTheRequestedDirection(direction: CutDirection) throws {
    // A pocket with an island: the outer wall has the material outside it, the island wall has it
    // inside, so for one cut type they wind opposite ways. Every ring parallel to a wall winds like it.
    let (ctx, ids) = F.document(shapePaths: pocketPaths)
    let sources = sourceLoops(pocketPaths, tolerance: ctx.tolerance)
    for c in PocketCase.all(direction: direction) {
        let op = PocketOperation(setup: OperationSetup(name: "Pocket", toolID: F.endMill.id, shapeIDs: ids), params: c.params)
        let tps = try op.generate(in: ctx)
        try #require(tps.count == (c.clearance ? 2 : 1), "\(c)")
        for tp in tps {
            let passes = cutDepth.passDepths(toolStepdown: tp.tool.stepdown).count
            #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty, "\(c)")
            var outer = 0, island = 0
            for lap in laps(of: tp, coords: ctx.coords, sources: sources) {
                let (observedDirection, _, loop) = observed(lap, closed: true, sources: sources)
                if Polygon2D.signedArea(sources[loop]) < 0 { island += 1 } else { outer += 1 }
                #expect(observedDirection == c.direction,
                        "\(c) [\(tp.name)]: lap along vector \(loop) near \(lap[0]) runs \(observedDirection.map { "\($0)" } ?? "nowhere")")
            }
            // Each toolpath cuts both walls on every pass (the clearance tool's rings, the finish tool's walls).
            #expect(outer >= passes && island >= passes,
                    "\(c) [\(tp.name)]: \(outer) outer and \(island) island lap(s) found, wanted \(passes) each")
        }
    }
}

@Test(arguments: CutDirection.allCases)
func pocketPlannerChainsRunTheRequestedDirectionIncludingRestPieces(direction: CutDirection) throws {
    // The planner's own chains, before emission. Rest machining cuts the rings into open pieces,
    // which must keep the direction of the ring they came from whatever order they are cut in.
    let sources = sourceLoops(pocketPaths, tolerance: 1e-4)
    let planner = PocketPlanner(region: sources, toolRadius: F.endMill.radius, stepover: F.endMill.stepover,
                                allowance: 0, tolerance: 1e-4, direction: direction)
    for start in [Vec2(0, 0), Vec2(6, 4), Vec2(3, 0), Vec2(0, 2), Vec2(3, 2)] {
        var chains: [(Chain2D, String)] = planner.offsetClearing(from: start).flatMap { $0 }.map { ($0, "offset") }
        for angle in [0.0, 45] {
            chains += planner.rasterClearing(angle: angle, profilePass: true, from: start).flatMap { $0 }
                .filter(\.isClosed).map { ($0, "raster \(angle)") }   // raster lines have no side
        }
        for fullWalls in [true, false] {
            let rest = planner.restClearing(clearanceRadius: F.bigEndMill.radius, from: start, fullWalls: fullWalls)
                .flatMap { $0 }
            // Without full walls (an intermediate clearance tool) the walls themselves come as pieces.
            let pieces = rest.filter { !$0.isClosed }.count
            #expect(fullWalls ? rest.count >= 2 : pieces >= 2, "rest fullWalls=\(fullWalls) from \(start): \(rest.count) chain(s), \(pieces) open")
            chains += rest.map { ($0, "rest fullWalls=\(fullWalls)") }
        }
        for (chain, label) in chains {
            #expect(isOffsetPath(chain.points, closed: chain.isClosed, sources: sources), "\(label) from \(start): not an offset path")
            let (observedDirection, _, loop) = observed(chain.points, closed: chain.isClosed, sources: sources)
            #expect(observedDirection == direction,
                    "\(direction) \(label) from \(start): \(chain.isClosed ? "loop" : "piece") along vector \(loop) near \(chain.start) runs \(observedDirection.map { "\($0)" } ?? "nowhere")")
        }
    }
}
