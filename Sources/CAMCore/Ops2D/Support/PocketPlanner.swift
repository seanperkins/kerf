import CADCore
import Foundation

/// 2D clearing patterns for a pocket region (material frame). Produces chains grouped by
/// connected component, already in cutting order; depth passes are applied by the caller.
public struct PocketPlanner: Sendable {
    /// Even-odd normalised pocket region (outer loops CCW, islands CW).
    public let region: [[Vec2]]
    public let toolRadius: Double
    public let stepover: Double
    public let allowance: Double
    public let tolerance: Double
    public let direction: CutDirection

    public init(region: [[Vec2]], toolRadius: Double, stepover: Double, allowance: Double,
                tolerance: Double, direction: CutDirection) {
        self.region = region
        self.toolRadius = toolRadius
        self.stepover = stepover
        self.allowance = allowance
        self.tolerance = tolerance
        self.direction = direction
    }

    /// Inward offset of the region by `distance` (round joins).
    public func inset(_ distance: Double) -> [[Vec2]] {
        guard distance != 0 else { return region }
        return GeomKernel.offset(region, by: -distance, join: .round, arcTolerance: tolerance)
            .map { Polygon2D.deduplicated($0, closed: true, tolerance: tolerance * 1e-3) }
            .filter { $0.count > 2 && abs(Polygon2D.signedArea($0)) > tolerance * tolerance }
    }

    /// Tool-centre boundary: region inset by radius + allowance.
    public var centerRegion: [[Vec2]] { inset(toolRadius + allowance) }

    /// Number of region components (outer loops) the tool centre cannot enter at all.
    public var unreachableComponents: Int {
        let centers = centerRegion
        return region.filter { Polygon2D.signedArea($0) > 0 }.filter { outer in
            !centers.contains { c in c.contains { Polygon2D.contains(outer, $0) } }
        }.count
    }

    /// Concentric offset levels from the wall inwards (level 0 = finishing contour).
    public func offsetLevels() -> [[[Vec2]]] {
        var levels: [[[Vec2]]] = []
        let base = toolRadius + allowance
        var k = 0
        while k < 100_000 {
            let lv = inset(base + Double(k) * stepover)
            if lv.isEmpty { break }
            levels.append(lv)
            k += 1
        }
        // A stepover wider than the radius could leave a core uncut: add a half step.
        if stepover > toolRadius, !levels.isEmpty {
            let lv = inset(base + (Double(k) - 0.5) * stepover)
            if !lv.isEmpty { levels.append(lv) }
        }
        return levels
    }

    /// Orients a region loop for the cut direction: climb keeps the wall (material) on the
    /// right, i.e. region loops as returned (outer CCW, islands CW); conventional reverses.
    func chain(_ loop: [Vec2]) -> Chain2D {
        Chain2D(points: direction == .climb ? loop : Array(loop.reversed()), isClosed: true)
    }

    // MARK: Components

    /// Groups chains by the level-0 outer loop containing them.
    func componentIndex(of p: Vec2, outers: [[Vec2]]) -> Int {
        var best = -1, bestArea = Double.infinity
        for (i, o) in outers.enumerated() where Polygon2D.contains(o, p) {
            let a = abs(Polygon2D.signedArea(o))
            if a < bestArea { bestArea = a; best = i }
        }
        if best >= 0 { return best }
        // Numerical edge case: nearest outer.
        return outers.indices.min { Polygon2D.distance(from: p, toLoop: outers[$0]) < Polygon2D.distance(from: p, toLoop: outers[$1]) } ?? 0
    }

    /// Orders tagged chains: components nearest-first; inside each, `rank` ascending
    /// (lower rank cut first), nearest neighbour within constraints. `allowReverse` lets an open
    /// chain start at its nearer end: right for a raster line, which has no side, wrong for a piece
    /// of an oriented ring, which would then cut its wall in the opposite direction.
    func order(_ items: [(chain: Chain2D, rank: Int, probe: Vec2)], outers: [[Vec2]], from start: Vec2,
               allowReverse: Bool,
               mustPrecede: (Chain2D, Int, Chain2D, Int) -> Bool = { _, ra, _, rb in ra < rb }) -> [[Chain2D]] {
        var groups: [Int: [(Chain2D, Int)]] = [:]
        for it in items { groups[componentIndex(of: it.probe, outers: outers), default: []].append((it.chain, it.rank)) }
        var cur = start
        var remaining = Set(groups.keys)
        var out: [[Chain2D]] = []
        while !remaining.isEmpty {
            // Nearest component by its lowest-rank chains.
            let next = remaining.min { a, b in
                minDistance(groups[a]!, cur, allowReverse: allowReverse) < minDistance(groups[b]!, cur, allowReverse: allowReverse)
            }!
            remaining.remove(next)
            let g = groups[next]!
            let preds: [Set<Int>] = g.map { item in
                Set(g.indices.filter { g[$0].1 < item.1 && mustPrecede(g[$0].0, g[$0].1, item.0, item.1) })
            }
            let ordered = ChainOrdering.nearestNeighbour(g.map(\.0), from: cur, allowReverse: allowReverse,
                                                         predecessors: preds, tolerance: tolerance)
            if let last = ordered.last { cur = last.end }
            out.append(ordered)
        }
        return out
    }

    private func minDistance(_ g: [(Chain2D, Int)], _ p: Vec2, allowReverse: Bool) -> Double {
        let lowest = g.map(\.1).min() ?? 0
        return g.filter { $0.1 == lowest }.map { c in
            if c.0.isClosed { return Polygon2D.distance(from: p, toLoop: c.0.points) }
            let fromStart = c.0.start.distance(to: p)
            return allowReverse ? min(fromStart, c.0.end.distance(to: p)) : fromStart
        }.min() ?? .infinity
    }

    // MARK: Strategies

    /// Contour-parallel clearing: innermost rings first, finishing on the walls, plus the cuts that cover the
    /// floor the rings leave uncut within the tool's reach (see `coverageCleanup`).
    public func offsetClearing(from start: Vec2) -> [[Chain2D]] {
        offsetClearingReport(from: start).groups
    }

    /// `offsetClearing` plus the area of floor within the tool's reach that is still farther than the
    /// coverage slack from every cut (zero unless the cleanup could not finish the job).
    public func offsetClearingReport(from start: Vec2) -> (groups: [[Chain2D]], uncoveredArea: Double) {
        let levels = offsetLevels()
        guard let outers0 = levels.first?.filter({ Polygon2D.signedArea($0) > 0 }), !outers0.isEmpty else { return ([], 0) }
        var items: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        for (k, lv) in levels.enumerated() {
            for loop in lv { items.append((chain(loop), levels.count - 1 - k, loop[0])) }
        }
        let cleanup = coverageCleanup(levels: levels, rings: items.map(\.chain))
        items += cleanup.fragments
        // A ring waits only for the deeper rings right next to it, so separate lobes and the rings around
        // islands are each cleared inside-out and linked at depth. A cleanup fragment has the rank of the ring
        // just outside it, so it waits for the ring just inside it.
        let reach = stepover * 1.5 + tolerance
        let groups = order(items, outers: outers0, from: start, allowReverse: false) { a, ra, b, rb in
            rb == ra + 1 && Self.loopsWithin(a.points, b.points, reach)
        }
        return (groups, cleanup.uncoveredArea)
    }

    // MARK: Coverage cleanup

    /// How far past the tool radius floor may sit from every cut and still count as cut: 2% of the
    /// diameter. This is the coverage promise of offset pocketing (the coverage test asserts it), apart
    /// from `allowance`, which is left on the walls on purpose.
    public static let coverageSlackFraction = 0.02
    var coverageSlack: Double { max(2 * toolRadius * Self.coverageSlackFraction, 2 * tolerance) }

    /// Cuts that cover the floor the rings leave behind. Rings a stepover apart leave floor uncut where
    /// the next ring is farther than the tool's reach: at a sharp corner the worst point on the diagonal
    /// is 0.59 stepovers from the nearest ring (the scallop shows from a stepover of 85% of the diameter),
    /// and at the narrow tip of a wedge or lobe the last ring ends well short of the point the tool can
    /// reach (a stud up to a stepover minus the radius wide). Floor the tool could reach but the rings
    /// leave more than `coverageSlack` from every cut is covered by the pieces of the ring halfway
    /// between the rings that lie in the zone around that floor: with a stepover under the diameter every
    /// point is within half a stepover of the half ring, so one halving suffices. (The half-step ring
    /// `offsetLevels` adds past the last full ring is the same idea for the middle of the pocket.) Returns
    /// that argument fails. `target` is the floor that has to be covered (default: everything the tool can
    /// reach; rest machining passes the part of it the earlier tools left), and a piece takes the rank
    /// `rankBase - k` of the ring k it was halved from (default `levels.count - 1`).
    func coverageCleanup(levels: [[[Vec2]]], rings: [Chain2D], over target: [[Vec2]]? = nil, rankBase: Int? = nil)
        -> (fragments: [(chain: Chain2D, rank: Int, probe: Vec2)], uncoveredArea: Double) {
        // Every floor point inside the tool-centre region is within one stepover of a ring (walk from it
        // straight to the nearest wall: the wall distance falls at rate 1 and crosses the ring's level),
        // and every point outside it is within the radius of ring 0. So rings no further apart than the
        // radius plus the slack leave nothing past the slack, at a corner or a tip too. (A planner with a
        // zero radius plans tool-centre paths for a caller that adds the tool itself, and needs no cleanup.)
        guard toolRadius > 0, stepover > toolRadius + coverageSlack else { return ([], 0) }
        let reachable = target ?? GeomKernel.offset(centerRegion, by: toolRadius, join: .round, arcTolerance: tolerance)
        guard !reachable.isEmpty else { return ([], 0) }
        func uncovered(_ walks: [[Vec2]]) -> [[Vec2]] {
            let covered = GeomKernel.offset(walks, by: toolRadius + coverageSlack, join: .round, end: .openRound,
                                            arcTolerance: tolerance)
            return withoutSlivers(GeomKernel.boolean(.difference, subject: reachable, clip: covered, fillRule: .nonZero),
                                  by: max(tolerance, 1e-5))
        }
        func area(_ loops: [[Vec2]]) -> Double { max(loops.reduce(0) { $0 + Polygon2D.signedArea($1) }, 0) }
        var walks = rings.map(\.walk)
        let rest = uncovered(walks)
        guard !rest.isEmpty else { return ([], 0) }
        let zone = GeomKernel.offset(rest, by: toolRadius, join: .round, arcTolerance: tolerance)
        var out: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        for k in levels.indices {
            // The half ring between ring k and ring k + 1 is cut with ring k.
            let half = inset(toolRadius + allowance + (Double(k) + 0.5) * stepover)
            for piece in ringPieces(half.map { chain($0).walk }, inside: zone, longerThan: max(tolerance * 4, coverageSlack)) {
                out.append((piece.chain, (rankBase ?? levels.count - 1) - k, piece.probe))
                walks.append(piece.chain.walk)
            }
        }
        return (out, area(uncovered(walks)))
    }

    /// `loops` without the slivers a boolean leaves along arcs: opened and closed again by `eps`.
    func withoutSlivers(_ loops: [[Vec2]], by eps: Double) -> [[Vec2]] {
        GeomKernel.offset(GeomKernel.offset(loops, by: -eps, arcTolerance: tolerance), by: eps, arcTolerance: tolerance)
    }

    /// The parts of the open `walks` (a ring walked from its start to its end) inside `zone`, as chains of
    /// the same direction: a part that is a whole ring comes back closed. Parts no longer than `longerThan`
    /// are dropped.
    func ringPieces(_ walks: [[Vec2]], inside zone: [[Vec2]], longerThan shortest: Double) -> [(chain: Chain2D, probe: Vec2)] {
        guard !walks.isEmpty else { return [] }
        let frags = GeomKernel.boolean(.intersection, subject: walks, clip: zone, fillRule: .nonZero, subjectsOpen: true)
        return frags.filter { $0.count > 1 && Polygon2D.length($0, closed: false) > shortest }.map { f in
            let closed = f.first!.distance(to: f.last!) <= tolerance * 1e-2 && f.count > 3
            let c = closed ? Chain2D(points: Array(f.dropLast()), isClosed: true) : Chain2D(points: f, isClosed: false)
            return (c, f[f.count / 2])
        }
    }

    /// True when some vertex of `a` lies within `d` of loop `b` (bounding boxes first).
    static func loopsWithin(_ a: [Vec2], _ b: [Vec2], _ d: Double) -> Bool {
        let ba = Rect2(points: a).insetBy(-d), bb = Rect2(points: b)
        guard ba.intersects(bb) else { return false }
        for p in a where bb.insetBy(-d).contains(p) {
            if Polygon2D.distance(from: p, toLoop: b) <= d { return true }
        }
        return false
    }

    /// Zig-zag raster at `angle` degrees, optionally followed (or preceded, `profileFirst`) by the
    /// wall contour.
    public func rasterClearing(angle: Double, profilePass: Bool, profileFirst: Bool = false,
                               from start: Vec2) -> [[Chain2D]] {
        let boundary = centerRegion
        let outers = boundary.filter { Polygon2D.signedArea($0) > 0 }
        guard !outers.isEmpty else { return [] }
        var items: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        for seg in rasterLines(in: boundary, angle: angle) {
            items.append((Chain2D(points: seg, isClosed: false), profileFirst ? 1 : 0, seg[seg.count / 2]))
        }
        if profilePass {
            for loop in boundary { items.append((chain(loop), profileFirst ? 0 : 1, loop[0])) }
        }
        return order(items, outers: outers, from: start, allowReverse: true)   // a raster line has no side
    }

    /// Parallel lines across `area` (spacing ≤ stepover) clipped to it.
    public func rasterLines(in area: [[Vec2]], angle: Double) -> [[Vec2]] {
        let rad = angle * .pi / 180
        let rotated = area.map { $0.map { $0.rotated(by: -rad) } }
        let b = Rect2(points: rotated.flatMap { $0 })
        guard !b.isEmpty, b.height >= 0 else { return [] }
        let eps = max(tolerance * 0.1, 1e-6)
        let span = max(b.height - 2 * eps, 0)
        let n = max(1, Int(ceil(span / stepover - 1e-9)))
        var lines: [[Vec2]] = []
        for i in 0...n {
            let y = b.min.y + eps + span * Double(i) / Double(n)
            lines.append([Vec2(b.min.x - 1, y).rotated(by: rad), Vec2(b.max.x + 1, y).rotated(by: rad)])
        }
        let clipped = GeomKernel.boolean(.intersection, subject: lines, clip: area, fillRule: .evenOdd, subjectsOpen: true)
        return clipped.filter { $0.count > 1 && Polygon2D.length($0, closed: false) > tolerance }
    }

    /// Rest machining after a larger clearance tool of radius `clearanceRadius`: the walls
    /// (level 0) plus ring fragments that reach material the big tool could not, and the cuts that cover
    /// the rest floor those leave (see `coverageCleanup`). With `fullWalls` off (an intermediate clearance
    /// tool) the walls are only cut near rest material.
    public func restClearing(clearanceRadius: Double, from start: Vec2, fullWalls: Bool = true) -> [[Chain2D]] {
        restClearingReport(clearanceRadius: clearanceRadius, from: start, fullWalls: fullWalls).groups
    }

    /// `restClearing` plus the area of rest floor within the tool's reach that is still farther than the
    /// coverage slack from every cut (zero unless the cleanup could not finish the job).
    public func restClearingReport(clearanceRadius: Double, from start: Vec2, fullWalls: Bool = true)
        -> (groups: [[Chain2D]], uncoveredArea: Double) {
        let levels = offsetLevels()
        guard let outers0 = levels.first?.filter({ Polygon2D.signedArea($0) > 0 }), !outers0.isEmpty else { return ([], 0) }
        let stock = inset(allowance)
        let bigCentres = inset(clearanceRadius + allowance)
        let reached = bigCentres.isEmpty ? [] : GeomKernel.offset(bigCentres, by: clearanceRadius, join: .round,
                                                                  arcTolerance: tolerance)
        var rest = GeomKernel.boolean(.difference, subject: stock, clip: reached, fillRule: .nonZero)
        // Drop slivers from flattening differences.
        rest = withoutSlivers(rest, by: max(tolerance * 4, 1e-5))
        var items: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        if fullWalls {
            for loop in levels[0] { items.append((chain(loop), 1_000_000, loop[0])) }
        }
        var uncoveredArea = 0.0
        if !rest.isEmpty {
            let zone = GeomKernel.offset(rest, by: toolRadius + stepover * 0.5, join: .round, arcTolerance: tolerance)
            for (k, lv) in levels.enumerated() where k > 0 || !fullWalls {
                for piece in ringPieces(lv.map { chain($0).walk }, inside: zone, longerThan: tolerance * 4) {
                    items.append((piece.chain, levels.count - k, piece.probe))
                }
            }
            // The rings of the pieces leave the same scallops and tip studs as whole rings do: cover the rest
            // floor this tool can reach that they miss (issue #66).
            let reachable = GeomKernel.offset(centerRegion, by: toolRadius, join: .round, arcTolerance: tolerance)
            let target = GeomKernel.boolean(.intersection, subject: rest, clip: reachable, fillRule: .nonZero)
            let cleanup = coverageCleanup(levels: levels, rings: items.map(\.chain), over: target, rankBase: levels.count)
            items += cleanup.fragments
            uncoveredArea = cleanup.uncoveredArea
        }
        // The pieces are cuts of oriented rings: they keep their direction, whichever end is nearer.
        return (order(items, outers: outers0, from: start, allowReverse: false), uncoveredArea)
    }
}
