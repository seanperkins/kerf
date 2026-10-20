import CADCore
import Foundation

/// Moulding: a cross-section swept along rails. Passes run parallel to the rail at offsets
/// t = 0, s, 2s … across the section width; at each offset the tool tip depth comes from a 1D
/// drop-cutter of the tool shape against the section, so the tool never cuts below the profile.
/// Exact for straight rails; on curved rails the section is applied along the rail normals.
public struct MouldingOperation: ToolpathOperation {
    public static let kind = OperationKind.moulding
    public var setup: OperationSetup
    public var params: MouldingParameters

    public init(setup: OperationSetup, params: MouldingParameters = MouldingParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let tol = context.tolerance
        guard let sid = params.sectionShapeID, let section = context.document.shape(id: sid) else {
            throw CAMError.invalidParameter("Choose the cross-section vector")
        }
        let rails = context.shapes(for: setup).filter { $0.id != sid }
        guard !rails.isEmpty else { throw CAMError.invalidParameter("Select the rail vectors (not only the section)") }
        let profile = try Self.sectionProfile(section, tolerance: tol)
        let step = min(max(params.stepover ?? tool.stepover, tol * 10), tool.diameter)
        let depths = Self.tipDepths(profile, tool: tool, step: step, extra: params.startDepth)

        // Rail offsets for each pass.
        let (closed, open) = ShapeGeometry.loops(of: rails, tolerance: tol)
        var passes: [(chains: [Chain2D], depth: Double)] = []
        for (t, d) in depths {
            var chains: [Chain2D] = []
            for line in open {
                let left = params.side != .right
                if let c = OpenOffset.oneSided(line, distance: t, left: left, tolerance: tol) {
                    chains.append(Chain2D(points: c, isClosed: false))
                }
            }
            if !closed.isEmpty {
                let plan = ProfileGeometry.loops(closed: closed, side: t > tol ? .inside : .on, offset: t,
                                                 direction: .climb, tolerance: tol)
                chains += plan.chains
            }
            if !chains.isEmpty && d > 1e-9 { passes.append((chains, d)) }
        }
        guard !passes.isEmpty else { throw CAMError.invalidGeometry("The section has no depth") }

        // Optional roughing levels (each pass limited to the level), then the finishing passes.
        var levels: [Double] = []
        let maxDepth = passes.map(\.depth).max()!
        if params.roughing, maxDepth > tool.stepdown + 1e-9 {
            levels = DepthSettings(cutDepth: maxDepth).passDepths(toolStepdown: tool.stepdown).dropLast()
        }
        let coords = context.coords
        var builder = ToolpathBuilder(coords: coords, tool: tool, units: context.units, tolerance: tol)
        var cur = coords.materialXY(fromMachine: context.document.job.home)
        var cleared: [Int: Double] = [:]
        for level in levels + [Double.infinity] {
            for (i, pass) in passes.enumerated() {
                let d = min(pass.depth, level)
                guard d > (cleared[i] ?? 0) + 1e-9 else { continue }
                for chain in ChainOrdering.nearestNeighbour(pass.chains, from: cur, tolerance: tol) {
                    let alc = ArcLengthChain(chain)
                    let lap = PassShaping.pass(on: alc, s0: 0, fromDepth: d, toDepth: d, ramp: RampSettings())
                    builder.cutChain(lap.points)
                    if let p = builder.position { cur = p.xy }
                }
                cleared[i] = d
            }
        }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .moulding, tool: tool, moves: builder.finish(),
                         metadata: ["passes": "\(passes.count)", "max depth": String(format: "%.4g", maxDepth)])]
    }

    /// The section as depth below its top for lateral offsets 0…width (upper envelope).
    public struct SectionProfile: Sendable {
        public var width: Double
        /// Samples (offset, depth), offsets ascending.
        public var samples: [(t: Double, depth: Double)]

        /// Depth at offset t (linear between samples; flat beyond the ends).
        public func depth(at t: Double) -> Double {
            guard let first = samples.first, let last = samples.last else { return 0 }
            if t <= first.t { return first.depth }
            if t >= last.t { return last.depth }
            var lo = 0, hi = samples.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if samples[mid].t <= t { lo = mid } else { hi = mid }
            }
            let a = samples[lo], b = samples[hi]
            let u = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
            return a.depth + (b.depth - a.depth) * u
        }
    }

    public static func sectionProfile(_ shape: Shape, tolerance: Double) throws -> SectionProfile {
        let polys = shape.paths.map { ($0.flattened(tolerance: tolerance), $0.isClosed) }.filter { $0.0.count > 1 }
        let all = polys.flatMap(\.0)
        let b = Rect2(points: all)
        guard b.width > tolerance, b.height > tolerance else {
            throw CAMError.invalidGeometry("The cross-section vector needs width and height")
        }
        var segs: [(Vec2, Vec2)] = []
        for (pts, closed) in polys {
            let walk = closed ? pts + [pts[0]] : pts
            segs += zip(walk, walk.dropFirst()).map { ($0, $1) }
        }
        let n = max(64, min(4000, Int((b.width / max(tolerance * 4, b.width / 4000)).rounded(.up))))
        var samples: [(Double, Double)] = []
        for k in 0...n {
            let x = b.min.x + b.width * Double(k) / Double(n)
            var top = -Double.infinity
            for (p, q) in segs {
                let lo = min(p.x, q.x), hi = max(p.x, q.x)
                guard x >= lo - 1e-12, x <= hi + 1e-12 else { continue }
                let y = hi - lo < 1e-12 ? max(p.y, q.y) : p.y + (q.y - p.y) * (x - p.x) / (q.x - p.x)
                top = max(top, y)
            }
            if top.isFinite { samples.append((x - b.min.x, b.max.y - top)) }
        }
        return SectionProfile(width: b.width, samples: samples)
    }

    /// Tool-tip depth at each pass offset: the deepest the tool can go without its shape cutting
    /// below the section anywhere under it (1D drop-cutter; surface flat beyond the section ends).
    static func tipDepths(_ profile: SectionProfile, tool: Tool, step: Double, extra: Double) -> [(t: Double, depth: Double)] {
        let r = tool.radius
        let n = max(1, Int((profile.width / step).rounded(.up)))
        let offsets = (0...n).map { min(profile.width, Double($0) * profile.width / Double(n)) }
        let m = 48
        // Also test where the section has a corner (a step's top edge is where the tool sits).
        let corners = profile.samples.map(\.t)
        return offsets.map { t in
            var best = Double.infinity
            func test(_ u: Double) {
                // Height of the tool's cutting surface above its tip at lateral distance u.
                let h = tool.heightAboveTip(atRadius: min(abs(u), r)) ?? 0
                best = min(best, profile.depth(at: t + u) + h)
            }
            for k in -m...m { test(r * Double(k) / Double(m)) }
            for c in corners where abs(c - t) <= r { test(c - t) }
            return (t, max(0, best) + max(extra, 0))
        }
    }
}
