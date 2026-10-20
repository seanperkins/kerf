import CADCore
import Foundation

/// Prism carving. The surface left inside a shape by a V-bit whose tip runs along the outline at
/// depth D is −D + distance-to-outline / tan(half angle), so choosing D = (widest inscribed
/// radius − tip radius) / tan(half angle) per shape makes the flanks meet at the material top
/// along the centreline: a raised, bevelled prism inside a V-groove.
public struct PrismOperation: ToolpathOperation {
    public static let kind = OperationKind.prism
    public var setup: OperationSetup
    public var params: PrismParameters

    public init(setup: OperationSetup, params: PrismParameters = PrismParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        guard tool.kind == .vBit || tool.kind == .engraving, let angle = tool.angle, angle > 0, angle < 180 else {
            throw CAMError.invalidParameter("Prism carving needs a V-bit")
        }
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let tol = context.tolerance
        let closed = ShapeGeometry.loops(of: shapes, tolerance: tol).closed
        guard !closed.isEmpty else { throw CAMError.invalidGeometry("Prism carving needs closed vectors") }
        let components = Self.components(Polygon2D.region(fromLoops: closed))
        guard !components.isEmpty else { throw CAMError.invalidGeometry("Selected vectors enclose no area") }

        let fullDepth = tool.vDepth(forWidth: tool.diameter)
        var limited = 0
        var jobs: [(loops: [Chain2D], depth: Double)] = []
        for comp in components {
            let r = Self.inscribedRadius(comp, tolerance: tol)
            var d = tool.vDepth(forWidth: 2 * r)
            if d > fullDepth + 1e-9 { d = fullDepth; limited += 1 }
            if let m = params.maxDepth, m > 0, d > m { d = m }
            guard d > tol else { continue }
            let plan = ProfileGeometry.loops(closed: comp, side: .on, offset: 0, direction: params.direction, tolerance: tol)
            jobs.append((plan.chains, d))
        }
        guard !jobs.isEmpty else { throw CAMError.invalidGeometry("The shapes are too narrow to carve") }

        let coords = context.coords
        var cur = coords.materialXY(fromMachine: context.document.job.home)
        var builder = ToolpathBuilder(coords: coords, tool: tool, units: context.units, tolerance: tol)
        var remaining = Array(jobs.indices)
        var deepest = 0.0
        while !remaining.isEmpty {
            // Nearest shape next; inside it, nearest loops first.
            let k = remaining.min { a, b in
                jobs[a].loops.map { Polygon2D.distance(from: cur, toLoop: $0.points) }.min()!
                    < jobs[b].loops.map { Polygon2D.distance(from: cur, toLoop: $0.points) }.min()!
            }!
            remaining.removeAll { $0 == k }
            let job = jobs[k]
            deepest = max(deepest, job.depth)
            let depth = DepthSettings(cutDepth: job.depth, passDepth: params.passDepth)
            try depth.validatePassDepth(toolStepdown: tool.stepdown)
            let passes = depth.passDepths(toolStepdown: tool.stepdown)
            for chain in ChainOrdering.nearestNeighbour(job.loops, from: cur, tolerance: tol) {
                let alc = ArcLengthChain(chain)
                var prev = 0.0, s0 = 0.0
                for d in passes {
                    let pass = PassShaping.pass(on: alc, s0: s0, fromDepth: prev, toDepth: d, ramp: RampSettings())
                    builder.cutChain(pass.points)
                    prev = d
                    s0 = pass.endS
                }
                if let p = builder.position { cur = p.xy }
            }
        }
        var meta = ["max depth": String(format: "%.4g", deepest)]
        if limited > 0 {
            meta["warning"] = "\(limited) shape(s) wider than the V-bit can reach; their tops are left flat"
        }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .prism, tool: tool,
                         moves: builder.finish(), metadata: meta)]
    }

    /// Splits an even-odd region into outer loops with the holes directly inside them.
    static func components(_ region: [[Vec2]]) -> [[[Vec2]]] {
        let outers = region.filter { Polygon2D.signedArea($0) > 0 }
        var comps = outers.map { [$0] }
        for hole in region where Polygon2D.signedArea(hole) < 0 {
            guard let p = hole.first else { continue }
            let owner = outers.indices.filter { Polygon2D.contains(outers[$0], p) }
                .min { abs(Polygon2D.signedArea(outers[$0])) < abs(Polygon2D.signedArea(outers[$1])) }
            if let o = owner { comps[o].append(hole) }
        }
        return comps
    }

    /// Radius of the largest circle inside the region (binary search on inward offsets).
    static func inscribedRadius(_ region: [[Vec2]], tolerance: Double) -> Double {
        let b = Rect2(points: region.flatMap { $0 })
        var lo = 0.0, hi = max(b.width, b.height) / 2
        for _ in 0..<40 where hi - lo > tolerance * 0.25 {
            let mid = (lo + hi) / 2
            let inner = GeomKernel.offset(region, by: -mid, join: .round, arcTolerance: tolerance)
            if inner.contains(where: { abs(Polygon2D.signedArea($0)) > 0 }) { lo = mid } else { hi = mid }
        }
        return lo
    }
}
