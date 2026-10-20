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
    /// (lower rank cut first), nearest neighbour within constraints.
    func order(_ items: [(chain: Chain2D, rank: Int, probe: Vec2)], outers: [[Vec2]], from start: Vec2,
               mustPrecede: (Chain2D, Int, Chain2D, Int) -> Bool = { _, ra, _, rb in ra < rb }) -> [[Chain2D]] {
        var groups: [Int: [(Chain2D, Int)]] = [:]
        for it in items { groups[componentIndex(of: it.probe, outers: outers), default: []].append((it.chain, it.rank)) }
        var cur = start
        var remaining = Set(groups.keys)
        var out: [[Chain2D]] = []
        while !remaining.isEmpty {
            // Nearest component by its lowest-rank chains.
            let next = remaining.min { a, b in
                minDistance(groups[a]!, cur) < minDistance(groups[b]!, cur)
            }!
            remaining.remove(next)
            let g = groups[next]!
            let preds: [Set<Int>] = g.map { item in
                Set(g.indices.filter { g[$0].1 < item.1 && mustPrecede(g[$0].0, g[$0].1, item.0, item.1) })
            }
            let ordered = ChainOrdering.nearestNeighbour(g.map(\.0), from: cur, allowReverse: true,
                                                         predecessors: preds, tolerance: tolerance)
            if let last = ordered.last { cur = last.end }
            out.append(ordered)
        }
        return out
    }

    private func minDistance(_ g: [(Chain2D, Int)], _ p: Vec2) -> Double {
        let lowest = g.map(\.1).min() ?? 0
        return g.filter { $0.1 == lowest }.map { c in
            c.0.isClosed ? Polygon2D.distance(from: p, toLoop: c.0.points) : min(c.0.start.distance(to: p), c.0.end.distance(to: p))
        }.min() ?? .infinity
    }

    // MARK: Strategies

    /// Contour-parallel clearing: innermost rings first, finishing on the walls.
    public func offsetClearing(from start: Vec2) -> [[Chain2D]] {
        let levels = offsetLevels()
        guard let outers0 = levels.first?.filter({ Polygon2D.signedArea($0) > 0 }), !outers0.isEmpty else { return [] }
        var items: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        for (k, lv) in levels.enumerated() {
            for loop in lv { items.append((chain(loop), levels.count - 1 - k, loop[0])) }
        }
        // A ring waits only for the deeper rings right next to it, so separate lobes and the
        // rings around islands are each cleared inside-out and linked at depth.
        let reach = stepover * 1.5 + tolerance
        return order(items, outers: outers0, from: start) { a, ra, b, rb in
            rb == ra + 1 && Self.loopsWithin(a.points, b.points, reach)
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

    /// Zig-zag raster at `angle` degrees, optionally followed by the wall contour.
    public func rasterClearing(angle: Double, profilePass: Bool, from start: Vec2) -> [[Chain2D]] {
        let boundary = centerRegion
        let outers = boundary.filter { Polygon2D.signedArea($0) > 0 }
        guard !outers.isEmpty else { return [] }
        var items: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        for seg in rasterLines(in: boundary, angle: angle) {
            items.append((Chain2D(points: seg, isClosed: false), 0, seg[seg.count / 2]))
        }
        if profilePass {
            for loop in boundary { items.append((chain(loop), 1, loop[0])) }
        }
        return order(items, outers: outers, from: start)
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
    /// (level 0) plus ring fragments that reach material the big tool could not.
    public func restClearing(clearanceRadius: Double, from start: Vec2) -> [[Chain2D]] {
        let levels = offsetLevels()
        guard let outers0 = levels.first?.filter({ Polygon2D.signedArea($0) > 0 }), !outers0.isEmpty else { return [] }
        let stock = inset(allowance)
        let bigCentres = inset(clearanceRadius + allowance)
        let reached = bigCentres.isEmpty ? [] : GeomKernel.offset(bigCentres, by: clearanceRadius, join: .round,
                                                                  arcTolerance: tolerance)
        var rest = GeomKernel.boolean(.difference, subject: stock, clip: reached, fillRule: .nonZero)
        // Drop slivers from flattening differences.
        let eps = max(tolerance * 4, 1e-5)
        rest = GeomKernel.offset(GeomKernel.offset(rest, by: -eps, arcTolerance: tolerance), by: eps, arcTolerance: tolerance)
        var items: [(chain: Chain2D, rank: Int, probe: Vec2)] = []
        for loop in levels[0] { items.append((chain(loop), 1_000_000, loop[0])) }
        if !rest.isEmpty {
            let zone = GeomKernel.offset(rest, by: toolRadius + stepover * 0.5, join: .round, arcTolerance: tolerance)
            for (k, lv) in levels.enumerated() where k > 0 {
                let open = lv.map { chain($0).walk }
                let frags = GeomKernel.boolean(.intersection, subject: open, clip: zone, fillRule: .nonZero, subjectsOpen: true)
                for f in frags where f.count > 1 && Polygon2D.length(f, closed: false) > tolerance * 4 {
                    let closed = f.first!.distance(to: f.last!) <= tolerance * 1e-2 && f.count > 3
                    let c = closed ? Chain2D(points: Array(f.dropLast()), isClosed: true) : Chain2D(points: f, isClosed: false)
                    items.append((c, levels.count - k, f[f.count / 2]))
                }
            }
        }
        return order(items, outers: outers0, from: start)
    }
}
