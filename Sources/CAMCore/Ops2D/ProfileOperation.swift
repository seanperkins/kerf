import CADCore
import Foundation

/// Profile: offset outside/inside/on the vector, multi-pass, climb/conventional, tabs, ramps, lead-in, allowance.
public struct ProfileOperation: ToolpathOperation {
    public static let kind = OperationKind.profile
    public var setup: OperationSetup
    public var params: ProfileParameters

    public init(setup: OperationSetup, params: ProfileParameters = ProfileParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let passes = params.depth.passDepths(toolStepdown: tool.stepdown)
        guard !passes.isEmpty else { throw CAMError.invalidParameter("Cut depth must be deeper than start depth") }
        let tol = context.tolerance

        let (closed, open) = ShapeGeometry.loops(of: shapes, tolerance: tol)
        let plan = ProfileGeometry.loops(closed: closed, side: params.side, offset: tool.radius + params.allowance,
                                         direction: params.direction, tolerance: tol)
        var chains = plan.chains
        chains += open.map { Chain2D(points: $0, isClosed: false) }
        guard !chains.isEmpty else {
            throw CAMError.invalidGeometry("The tool does not fit inside the selected vectors")
        }

        let coords = context.coords
        let home = coords.materialXY(fromMachine: context.document.job.home)
        let ordered = ChainOrdering.nearestNeighbour(chains, from: home, allowReverse: true,
                                                     predecessors: ChainOrdering.innerFirstPredecessors(chains),
                                                     tolerance: tol)
        var builder = ToolpathBuilder(coords: coords, tool: tool, units: context.units, tolerance: tol,
                                      fitArcs: params.preferArcs)
        var manualCenters: [[Double]]?
        if params.tabs.isEnabled, let anchors = params.tabs.manualTabs {
            manualCenters = TabAnchors.centers(for: anchors, loops: ordered.map { ArcLengthChain($0) },
                                               document: context.document, tolerance: tol)
        }
        for (i, chain) in ordered.enumerated() {
            cut(chain, passes: passes, tool: tool, wasteRegion: plan.wasteRegion, manualTabs: manualCenters?[i],
                builder: &builder, tolerance: tol)
        }
        var meta: [String: String] = [:]
        if plan.droppedLoops > 0 { meta["warning"] = "\(plan.droppedLoops) vector(s) too small for the tool" }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .profile, tool: tool,
                         moves: builder.finish(), metadata: meta)]
    }

    /// `manualTabs`: user-placed tab centres for this loop (nil = automatic layout).
    private func cut(_ chain: Chain2D, passes: [Double], tool: Tool, wasteRegion: WasteSide, manualTabs: [Double]?,
                     builder: inout ToolpathBuilder, tolerance tol: Double) {
        let alc = ArcLengthChain(chain)
        guard alc.length > tol else { return }
        let start = params.depth.startDepth
        if !chain.isClosed {
            // Open vectors: cut on the line, alternating direction each pass.
            var forward = true
            var prev = start
            let backward = ArcLengthChain(chain.reversed())
            for d in passes {
                let pass = PassShaping.pass(on: forward ? alc : backward, s0: 0, fromDepth: prev, toDepth: d,
                                            ramp: params.ramp)
                builder.cutChain(pass.points)
                prev = d
                forward.toggle()
            }
            return
        }

        var tabs: TabLayout?
        if params.tabs.isEnabled {
            if let manual = manualTabs {
                tabs = TabLayout(loopLength: alc.length, centers: manual, settings: params.tabs,
                                 toolDiameter: tool.diameter, cutDepth: params.depth.cutDepth)
            } else {
                tabs = TabLayout(loopLength: alc.length, settings: params.tabs, toolDiameter: tool.diameter,
                                 cutDepth: params.depth.cutDepth)
            }
        }
        let useLeads = params.lead.type != .none && params.lead.distance > 0
        var ramp = params.ramp
        if useLeads { ramp.isEnabled = false }
        let overcut = max(0, params.lead.overcut)
        var s0 = 0.0
        var prev = start
        for (k, d) in passes.enumerated() {
            let isLast = k == passes.count - 1
            var pass = PassShaping.pass(on: alc, s0: s0, fromDepth: prev, toDepth: d, ramp: ramp,
                                        overcut: overcut, spiralFinish: isLast)
            if let tabs { pass = tabs.apply(to: pass, chain: alc) }
            var pts = pass.points
            if useLeads {
                let t0 = alc.tangent(at: s0), t1 = alc.tangent(at: pass.endS)
                let inPts = Leads.leadIn(to: alc.point(at: s0), tangent: t0,
                                         waste: wasteRegion.normal(at: alc.point(at: s0), tangent: t0),
                                         settings: params.lead, tolerance: tol)
                let endP = alc.point(at: pass.endS)
                let outPts = Leads.leadOut(from: endP, tangent: t1,
                                           waste: wasteRegion.normal(at: endP, tangent: t1),
                                           settings: params.lead, tolerance: tol)
                pts = inPts.map { CutPoint($0, depth: d) } + pts + outPts.map { CutPoint($0, depth: d) }
            }
            // With leads every pass re-enters at the same lead-in, already cut to `prev`.
            builder.cutChain(pts, clearedDepth: useLeads && k > 0 ? prev : 0)
            prev = d
            // Without leads the next pass starts where this one ended (no retract).
            if !useLeads { s0 = pass.endS }
        }
    }
}

/// Tells which side of a toolpath loop is waste (for lead-ins).
public struct WasteSide: Sendable {
    /// Tool-centre region (even-odd loops).
    public var region: [[Vec2]]
    /// Waste lies inside `region` (inside profiles) or outside it (outside / on).
    public var wasteInside: Bool
    public var probe: Double

    /// Unit normal pointing to the waste at `p` for travel direction `t`.
    public func normal(at p: Vec2, tangent t: Vec2) -> Vec2 {
        let left = t.perpendicular
        let leftInside = Polygon2D.regionContains(region, p + left * probe)
        return leftInside == wasteInside ? left : -left
    }
}

/// Profile toolpath loops from closed vectors.
public enum ProfileGeometry {
    public struct Plan: Sendable {
        public var chains: [Chain2D]
        public var wasteRegion: WasteSide
        /// Input loops that vanished (tool too large for an inside cut).
        public var droppedLoops: Int
    }

    /// Offsets the even-odd region of `closed` by `offset` (outside grows, inside shrinks,
    /// on = none) and orients the loops for the cut direction (climb on a clockwise spindle
    /// keeps the finished part on the right of travel).
    public static func loops(closed: [[Vec2]], side: ProfileSide, offset: Double, direction: CutDirection,
                             tolerance: Double) -> Plan {
        let region = Polygon2D.region(fromLoops: closed)
        var loops: [[Vec2]]
        switch side {
        case .on:
            loops = closed.map { Polygon2D.signedArea($0) < 0 ? $0.reversed() : $0 }
        case .outside:
            loops = GeomKernel.offset(region, by: max(offset, 0), join: .round, arcTolerance: tolerance)
        case .inside:
            loops = GeomKernel.offset(region, by: -max(offset, 0), join: .round, arcTolerance: tolerance)
        }
        loops = loops.map { Polygon2D.deduplicated($0, closed: true, tolerance: tolerance * 1e-3) }.filter { $0.count > 2 }
        // Region loops come back with the region on the left (outer CCW, holes CW).
        // Part on the left for outside/on cuts, on the right for inside cuts.
        let partOnLeft = side != .inside
        let climb = direction == .climb
        // Climb ⇒ part on the right of travel.
        let reverse = partOnLeft == climb
        let chains = loops.map { Chain2D(points: reverse ? Array($0.reversed()) : $0, isClosed: true) }
        let dropped = side == .inside ? max(0, region.count - loops.count) : 0
        let wasteRegion = WasteSide(region: side == .on ? region : loops, wasteInside: side == .inside,
                                    probe: max(tolerance * 4, 1e-4))
        return Plan(chains: chains, wasteRegion: wasteRegion, droppedLoops: dropped)
    }
}
