import CADCore
import Foundation

/// Moulding: a cross-section swept along rails. Passes run parallel to the rail at offsets
/// t = 0, s, 2s … across the section width; at each offset the tool tip depth comes from a 1D
/// drop-cutter of the tool shape against the section, so the tool never cuts below the profile.
/// Exact for straight rails. Curved or cornered rails (and closed rails) use the swept surface
/// (`MouldingSurface`) and a 2D drop-cutter along each pass instead.
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
        let left = params.side != .right
        // Straight open rails: the 1D drop-cutter is exact. Anything with a bend or a corner
        // uses the swept surface and a 2D drop-cutter (round 2).
        let surface: DropCutter? = try Self.allStraight(open, tolerance: tol) && closed.isEmpty ? nil
            : DropCutter(map: MouldingSurface.heightmap(profile, closed: closed, open: open, left: left,
                                                        toolRadius: tool.radius, step: step, tolerance: tol),
                         cutter: CutterProfile(tool: tool))
        let deepest = (profile.samples.map(\.depth).max() ?? 0) + max(params.startDepth, 0)
        // Cut points of one (already ordered) chain at a pass's 1D depth `d`.
        func cutPoints(_ chain: Chain2D, d: Double) -> [CutPoint] {
            guard let drop = surface else {
                return PassShaping.pass(on: ArcLengthChain(chain), s0: 0, fromDepth: d, toDepth: d, ramp: RampSettings()).points
            }
            let pts = Self.densify(chain.walk, spacing: max(drop.map.cellSize, tol * 4)).map { p in
                CutPoint(p, depth: min(deepest, max(0, drop.depth(at: p)) + max(params.startDepth, 0)))
            }
            return Self.simplify(pts, tolerance: tol)
        }
        var passes: [(chains: [Chain2D], d1: Double, depth: Double)] = []
        for (t, d) in depths {
            var chains: [Chain2D] = []
            for line in open {
                if let c = OpenOffset.oneSided(line, distance: t, left: left, tolerance: tol) {
                    chains.append(Chain2D(points: c, isClosed: false))
                }
            }
            if !closed.isEmpty {
                let plan = ProfileGeometry.loops(closed: closed, side: t > tol ? .inside : .on, offset: t,
                                                 direction: .climb, tolerance: tol)
                chains += plan.chains
            }
            let depth = surface == nil ? d : chains.flatMap { cutPoints($0, d: d) }.map(\.depth).max() ?? 0
            if !chains.isEmpty && depth > 1e-9 { passes.append((chains, d, depth)) }
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
                    let pts = cutPoints(chain, d: pass.d1).map { CutPoint($0.xy, depth: min($0.depth, level)) }
                    guard pts.contains(where: { $0.depth > 1e-9 }) else { continue }
                    builder.cutChain(pts)
                    if let p = builder.position { cur = p.xy }
                }
                cleared[i] = d
            }
        }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .moulding, tool: tool, moves: builder.finish(),
                         metadata: ["passes": "\(passes.count)", "max depth": String(format: "%.4g", maxDepth)])]
    }

    /// True when every open rail is a single straight line (all points collinear).
    static func allStraight(_ open: [[Vec2]], tolerance: Double) -> Bool {
        open.allSatisfy { line in
            guard let a = line.first, let b = line.last, a.distance(to: b) > tolerance else { return false }
            let d = (b - a) * (1 / a.distance(to: b))
            return line.allSatisfy { abs(d.cross($0 - a)) <= tolerance } &&
                zip(line, line.dropFirst()).allSatisfy { ($1 - $0).dot(d) >= -tolerance }
        }
    }

    static func densify(_ pts: [Vec2], spacing: Double) -> [Vec2] {
        guard var prev = pts.first else { return [] }
        var out = [prev]
        for p in pts.dropFirst() {
            let n = max(1, Int((prev.distance(to: p) / spacing).rounded(.up)))
            for k in 1...n { out.append(prev.lerp(to: p, Double(k) / Double(n))) }
            prev = p
        }
        return out
    }

    /// Drops points that lie within `tolerance` of the 3D line through their neighbours.
    static func simplify(_ pts: [CutPoint], tolerance: Double) -> [CutPoint] {
        guard pts.count > 2 else { return pts }
        var out = [pts[0]]
        for k in 1..<(pts.count - 1) {
            let a = out.last!, p = pts[k], b = pts[k + 1]
            let ab = Vec3(b.xy - a.xy, z: b.depth - a.depth), ap = Vec3(p.xy - a.xy, z: p.depth - a.depth)
            let len2 = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z
            let t = len2 > 0 ? (ap.x * ab.x + ap.y * ab.y + ap.z * ab.z) / len2 : 0
            let ex = ap.x - ab.x * t, ey = ap.y - ab.y * t, ez = ap.z - ab.z * t
            if t <= 0 || t >= 1 || (ex * ex + ey * ey + ez * ez).squareRoot() > tolerance { out.append(p) }
        }
        out.append(pts[pts.count - 1])
        return out
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
