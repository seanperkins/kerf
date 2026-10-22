import CADCore
import Foundation
import Testing
@testable import CAMCore

// Cut direction is a safety property: a climb cut on a clockwise spindle keeps the material on the
// right of travel, so a loop that comes out wound the other way tears the edge out of plywood.
// These tests read the emitted toolpath back, find every closed lap, work out which side of it the
// material is on, and check its winding against the requested direction, over every option that
// could reverse a loop on the way out: side, corner style, leads, last-pass reverse, ramps, tabs,
// ordering, start points, islands, raster walls and rest machining.

private typealias F = Ops2DFixture

/// The cutting moves of `tp` between rapids, as dense material-frame points (arcs sampled).
private func runs(of tp: Toolpath, coords: MachineCoordinates) -> [[Vec2]] {
    var runs: [[Vec2]] = []
    var current: [Vec2] = []
    var pos: Vec3?
    for m in tp.moves {
        if case .rapid(let p) = m {
            if !current.isEmpty { runs.append(current); current = [] }
            pos = p
        } else if let target = m.target {
            let prefix: [Move] = pos.map { [.rapid(to: $0)] } ?? []
            current += F.densePoints(prefix + [m]).map { coords.materialXY(fromMachine: $0.xy) }
            pos = target
        }
    }
    if !current.isEmpty { runs.append(current) }
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
                    if abs(Polygon2D.signedArea(lap)) > 0.02, parallelDistance(lap, sources: sources) != nil {
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

/// The distance at which a lap runs parallel to the source vectors, or nil when it does not: an
/// offset loop keeps one distance from the region's boundary all the way round (a mitred corner
/// reaches √2 of it), while a closed figure that a raster and its links happen to draw does not.
private func parallelDistance(_ lap: [Vec2], sources: [[Vec2]]) -> Double? {
    // Sample along each edge too: a straight raster line only touches the walls at its ends.
    var samples: [Vec2] = []
    for i in 0..<lap.count {
        let a = lap[i], b = lap[(i + 1) % lap.count]
        for k in 0..<8 { samples.append(a + (b - a) * (Double(k) / 8)) }
    }
    let ds = samples.map { v in sources.map { Polygon2D.distance(from: v, toLoop: $0) }.min()! }
    let lo = ds.min()!, hi = ds.max()!
    return hi <= lo * 1.5 + 2e-3 ? lo : nil
}

/// Winding number of `q` around the polyline `poly` taken as a closed loop (a retraced zig-zag
/// contributes nothing, a lap traced twice counts twice, so this is the point-in-lap test to use).
private func winding(_ poly: [Vec2], _ q: Vec2) -> Int {
    var w = 0
    for i in 0..<poly.count {
        let a = poly[i], b = poly[(i + 1) % poly.count]
        if a.y <= q.y {
            if b.y > q.y, (b - a).cross(q - a) > 0 { w += 1 }
        } else if b.y <= q.y, (b - a).cross(q - a) < 0 {
            w -= 1
        }
    }
    return w
}

/// Which side of a lap the material is on. From the lap point nearest a source vector (preferring
/// one whose nearest vector point is mid-edge, so the probe never skims a corner), a probe is pushed
/// just past that vector when the vector lies inside the lap, or just inside the lap when it does
/// not, and tested against the source region (the vectors' even-odd area).
/// Returns whether the probe is in the region and how far the lap sits from the vector.
private func probe(_ lap: [Vec2], sources: [[Vec2]]) -> (inRegion: Bool, distance: Double, note: String) {
    struct Candidate { var v: Vec2; var q: Vec2; var d: Double; var corner: Double }
    let vertices = sources.flatMap { $0 }
    var candidates: [Candidate] = []
    for i in 0..<lap.count {
        for v in [lap[i], (lap[i] + lap[(i + 1) % lap.count]) * 0.5] {
            var best = Candidate(v: v, q: v, d: .infinity, corner: 0)
            for src in sources {
                for j in 0..<src.count {
                    let c = Polygon2D.closestPoint(onSegment: src[j], src[(j + 1) % src.count], to: v).point
                    let d = c.distance(to: v)
                    if d < best.d { best = Candidate(v: v, q: c, d: d, corner: vertices.map { $0.distance(to: c) }.min() ?? 0) }
                }
            }
            candidates.append(best)
        }
    }
    let dmin = candidates.map(\.d).min()!
    let best = candidates.filter { $0.d <= dmin + 2e-3 }.max { $0.corner < $1.corner }!
    let delta = 1e-3
    guard best.d > 1e-6 else {   // a cut on the line: the lap's own interior is the probe
        let centre = lap.reduce(Vec2.zero) { $0 + $1 } * (1 / Double(lap.count))
        return (Polygon2D.regionContains(sources, centre), 0, "on the line")
    }
    let u = (best.q - best.v) * (1 / best.d)
    let sourceInward = winding(lap, best.v + u * min(delta, best.d / 2)) != 0
    let point = sourceInward ? best.v + u * (best.d + delta) : best.v - u * delta
    let inRegion = Polygon2D.regionContains(sources, point)
    let box = Rect2(points: lap)
    return (inRegion, best.d, "vector \(sourceInward ? "inside" : "outside") the lap at \(best.d), probe \(point) \(inRegion ? "in" : "outside") the region; lap of \(lap.count) points spans \(box.min) to \(box.max)")
}

/// Winding a cut should have: climb keeps the material on the right of travel, so a lap with the
/// material inside it runs clockwise (negative area) and one with the material outside runs
/// counter-clockwise; conventional is the opposite.
private func expectedSign(materialInside: Bool, direction: CutDirection) -> Double {
    (direction == .climb) == materialInside ? -1 : 1
}

private func sign(_ x: Double) -> Double { x < 0 ? -1 : 1 }

// MARK: Profiles

private struct ProfileCase: CustomStringConvertible {
    var side: ProfileSide
    var direction: CutDirection
    var sharp: Bool
    var lead: LeadType
    var lastPass: ProfileLastPass?
    var ramp: RampType?
    var tabs: Bool
    var order: ProfileOrder
    var start: ProfileStartPoint

    var description: String {
        "\(side)/\(direction) sharp=\(sharp) lead=\(lead) lastPass=\(lastPass.map { "\($0.reverseDirection ? "reversed" : "same")" } ?? "none") "
            + "ramp=\(ramp.map { "\($0)" } ?? "off") tabs=\(tabs) order=\(order) start=\(start)"
    }

    static let lastPassAllowance = 0.06

    var params: ProfileParameters {
        var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.3), side: side, direction: direction)
        p.sharpCorners = sharp
        p.lead = LeadSettings(type: lead, distance: 0.25, overcut: lead == .arc ? 0.1 : 0)
        p.lastPass = lastPass
        if let ramp { p.ramp = RampSettings(isEnabled: true, type: ramp, length: 0.5, maxAngle: 15) }
        p.tabs = TabSettings(isEnabled: tabs, length: 0.25, thickness: 0.1, countPerPath: 2)
        p.order = order
        p.startPoint = start
        return p
    }

    /// Every combination for one side and direction.
    static func all(side: ProfileSide, direction: CutDirection) -> [ProfileCase] {
        var out: [ProfileCase] = []
        let lastPasses: [ProfileLastPass?] = side == .on ? [nil]
            : [nil, ProfileLastPass(allowance: lastPassAllowance, reverseDirection: false),
               ProfileLastPass(allowance: lastPassAllowance, reverseDirection: true)]
        for sharp in [false, true] {
            for lead in LeadType.allCases {
                for lastPass in lastPasses {
                    for ramp in [nil, RampType.zigzag, .spiral, .smooth] {
                        // Tabs shape the pass after leads are added, so they are varied without leads only.
                        for tabs in (lead == .none ? [false, true] : [false]) {
                            for (order, start) in [(ProfileOrder.nearest, ProfileStartPoint.nearest),
                                                   (.leftToRight, .vectorStart), (.grid, .top)] {
                                out.append(ProfileCase(side: side, direction: direction, sharp: sharp, lead: lead,
                                                       lastPass: lastPass, ramp: ramp, tabs: tabs, order: order, start: start))
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}

/// Runs one profile over `paths` and checks every lap's winding. Returns the number of laps checked.
@discardableResult
private func checkProfile(_ c: ProfileCase, paths: [Path], asOneShape: Bool = false,
                          sourceLocation: SourceLocation = #_sourceLocation) throws -> Int {
    let (ctx, ids) = asOneShape ? F.document(shapePaths: paths) : F.document(paths)
    let op = ProfileOperation(setup: OperationSetup(name: "Profile", toolID: F.endMill.id, shapeIDs: ids), params: c.params)
    let tps = try op.generate(in: ctx)
    #expect(tps.count == 1, "\(c)", sourceLocation: sourceLocation)
    let tp = tps[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty, "\(c)", sourceLocation: sourceLocation)
    let sources = Polygon2D.region(fromLoops: paths.map { $0.flattened(tolerance: ctx.tolerance) })
    let found = laps(of: tp, coords: ctx.coords, sources: sources)
    if found.count < sources.count {
        let detail = runs(of: tp, coords: ctx.coords).map { "\($0.count) pts \($0.prefix(3).map { "\($0)" }) … \($0.suffix(2).map { "\($0)" })" }
        Issue.record("\(c): only \(found.count) lap(s) found in \(tp.moves.count) moves; runs: \(detail)", sourceLocation: sourceLocation)
    }
    for lap in found {
        // The part is the region for outside/on cuts and everything else for inside cuts.
        let (inRegion, d, note) = probe(lap, sources: sources)
        let materialInside = inRegion == (c.side != .inside)
        // Roughing laps run outside the last pass's allowance; the finishing lap is the one at the tool radius.
        let isFinish = c.lastPass != nil && d < F.endMill.radius + ProfileCase.lastPassAllowance / 2
        let direction = isFinish && c.lastPass!.reverseDirection ? c.direction.reversed : c.direction
        let want = expectedSign(materialInside: materialInside, direction: direction)
        let area = Polygon2D.signedArea(lap)
        #expect(sign(area) == want,
                "\(c): lap near \(lap[0]) (\(isFinish ? "finish" : "rough"), material \(materialInside ? "inside" : "outside")) has area \(area), expected \(want > 0 ? "CCW" : "CW") [\(note)]",
                sourceLocation: sourceLocation)
    }
    return found.count
}

@Test(arguments: ProfileSide.allCases, CutDirection.allCases)
func profileLoopsKeepTheRequestedDirectionUnderEveryOption(side: ProfileSide, direction: CutDirection) throws {
    // Two parts, so ordering and start points have something to reorder.
    let paths = [F.rect(1, 1, 3, 2), F.rect(5, 1, 2, 2)]
    for c in ProfileCase.all(side: side, direction: direction) {
        try checkProfile(c, paths: paths)
    }
}

@Test(arguments: [ProfileSide.outside, .inside], CutDirection.allCases)
func profileHoleLoopsRunOppositeToTheOuterLoop(side: ProfileSide, direction: CutDirection) throws {
    // A ring: the material is on the other side of the hole's loop, so it winds the other way.
    let ring = [F.rect(0, 0, 6, 4), F.rect(2, 1, 2, 2)]
    for lastPass in [nil, ProfileLastPass(allowance: ProfileCase.lastPassAllowance, reverseDirection: true)] {
        for lead in LeadType.allCases {
            let c = ProfileCase(side: side, direction: direction, sharp: false, lead: lead, lastPass: lastPass,
                                ramp: nil, tabs: false, order: .nearest, start: .nearest)
            let n = try checkProfile(c, paths: ring, asOneShape: true)
            #expect(n >= 2, "\(c): expected the outer and the hole loop")
        }
    }
}

// MARK: Pockets

private struct PocketCase: CustomStringConvertible {
    var direction: CutDirection
    var strategy: PocketStrategy
    var profileFirst: Bool
    var ramp: RampType?
    var clearance: Bool

    var description: String {
        "\(direction) \(strategy) profileFirst=\(profileFirst) ramp=\(ramp.map { "\($0)" } ?? "off") clearance=\(clearance)"
    }

    var params: PocketParameters {
        var p = PocketParameters(depth: DepthSettings(cutDepth: 0.3), strategy: strategy, direction: direction)
        p.profilePassFirst = profileFirst
        if let ramp { p.ramp = RampSettings(isEnabled: true, type: ramp, length: 0.5, maxAngle: 15) }
        if clearance { p.clearanceToolIDs = [F.bigEndMill.id] }
        return p
    }

    static func all(direction: CutDirection) -> [PocketCase] {
        var out: [PocketCase] = []
        for strategy in [PocketStrategy.offset, .raster(angle: 0, profilePass: true), .raster(angle: 45, profilePass: true)] {
            for profileFirst in [false, true] {
                for ramp in [nil, RampType.zigzag, .spiral, .smooth] {
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

@Test(arguments: CutDirection.allCases)
func pocketWallsAndIslandWallsKeepTheRequestedDirection(direction: CutDirection) throws {
    // A pocket with an island: the outer wall has the material outside it, the island wall has it
    // inside, so for one cut type they wind opposite ways. Every ring parallel to a wall winds like it.
    let paths = [F.rect(0, 0, 6, 4), F.rect(2.25, 1.5, 1.5, 1)]
    for c in PocketCase.all(direction: direction) {
        let (ctx, ids) = F.document(shapePaths: paths)
        let op = PocketOperation(setup: OperationSetup(name: "Pocket", toolID: F.endMill.id, shapeIDs: ids), params: c.params)
        let tps = try op.generate(in: ctx)
        #expect(tps.count == (c.clearance ? 2 : 1), "\(c)")
        let sources = Polygon2D.region(fromLoops: paths.map { $0.flattened(tolerance: ctx.tolerance) })
        var outerLaps = 0, islandLaps = 0
        for tp in tps {
            #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty, "\(c)")
            for lap in laps(of: tp, coords: ctx.coords, sources: sources) {
                // The pocket region is waste; a lap with material inside it runs round the island.
                let (inRegion, _, note) = probe(lap, sources: sources)
                let island = !inRegion
                if island { islandLaps += 1 } else { outerLaps += 1 }
                let want = expectedSign(materialInside: island, direction: c.direction)
                let area = Polygon2D.signedArea(lap)
                #expect(sign(area) == want,
                        "\(c) [\(tp.name)]: lap near \(lap[0]) along the \(island ? "island" : "outer wall") has area \(area), expected \(want > 0 ? "CCW" : "CW") [\(note)]")
            }
        }
        #expect(outerLaps >= 1 && islandLaps >= 1, "\(c): \(outerLaps) outer and \(islandLaps) island lap(s) found")
    }
}
