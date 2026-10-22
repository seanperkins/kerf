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
        try params.depth.validatePassDepth(toolStepdown: tool.stepdown)
        let passes = params.depth.passDepths(toolStepdown: tool.stepdown)
        guard !passes.isEmpty else { throw CAMError.invalidParameter("Cut depth must be deeper than start depth") }
        let tol = context.tolerance

        let (closed, open) = ShapeGeometry.loops(of: shapes, tolerance: tol)
        let lastPass = effectiveLastPass(tolerance: tol)
        let finalOffset = tool.radius + params.allowance
        let join: GeomKernel.Join = params.sharpCorners == true ? .miter(limit: ProfileGeometry.sharpMiterLimit) : .round
        let plan = ProfileGeometry.loops(closed: closed, side: params.side, offset: finalOffset + (lastPass?.allowance ?? 0),
                                         direction: params.direction, tolerance: tol, join: join)
        let finishPlan = lastPass.map {
            ProfileGeometry.loops(closed: closed, side: params.side, offset: finalOffset,
                                  direction: $0.reverseDirection ? params.direction.reversed : params.direction,
                                  tolerance: tol, join: join)
        }
        var chains = plan.chains
        var openOffsetFailures = 0
        let openSide = params.openVectorSide ?? .on
        for line in open {
            if openSide == .on {
                chains.append(Chain2D(points: line, isClosed: false))
            } else if let shifted = OpenOffset.oneSided(line, distance: finalOffset, left: openSide == .left, tolerance: tol) {
                chains.append(Chain2D(points: shifted, isClosed: false))
            } else {
                openOffsetFailures += 1
                chains.append(Chain2D(points: line, isClosed: false))
            }
        }
        guard !chains.isEmpty || !(finishPlan?.chains.isEmpty ?? true) else {
            throw CAMError.invalidGeometry("The tool does not fit inside the selected vectors")
        }

        let coords = context.coords
        let home = coords.materialXY(fromMachine: context.document.job.home)
        var builder = ToolpathBuilder(coords: coords, tool: tool, units: context.units, tolerance: tol,
                                      fitArcs: params.preferArcs)
        let sourceStarts = closed.compactMap(\.first)
        let shapeLoops = shapes.map { s in s.paths.map { $0.flattened(tolerance: tol) } }
        let roughTabs = cutLoops(chains, passes: passes, from: home, tool: tool, wasteRegion: plan.wasteRegion,
                                 sourceStarts: sourceStarts, shapeLoops: shapeLoops, context: context,
                                 builder: &builder)
        if let lastPass, let finishPlan {
            // Last pass: removes the side allowance the roughing passes left on the wall. Its loops
            // start wherever the roughing ended, so automatic tabs would land elsewhere and the lap
            // would cut the roughing tabs away; the roughing tab positions are reused instead.
            let finishPasses = lastPass.fullDepth ? [params.depth.cutDepth] : passes
            _ = cutLoops(finishPlan.chains, passes: finishPasses, from: builder.position?.xy ?? home, tool: tool,
                         wasteRegion: finishPlan.wasteRegion, sourceStarts: sourceStarts, shapeLoops: shapeLoops,
                         inheritedTabs: (points: roughTabs, within: lastPass.allowance + 4 * tol + 1e-6),
                         context: context, builder: &builder)
        }
        var meta: [String: String] = [:]
        var warnings: [String] = []
        let dropped = finishPlan?.droppedLoops ?? plan.droppedLoops
        if dropped > 0 { warnings.append("\(dropped) vector(s) too small for the tool") }
        if openOffsetFailures > 0 {
            warnings.append("\(openOffsetFailures) open vector(s) could not be offset to the \(openSide.rawValue) and were cut on the line")
        }
        if params.side != .on && !open.isEmpty && openSide == .on {
            warnings.append("\(open.count) open vector(s) cut on the line (close them to cut \(params.side == .outside ? "outside" : "inside"))")
        }
        if !warnings.isEmpty { meta["warning"] = warnings.joined(separator: "; ") }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .profile, tool: tool,
                         moves: builder.finish(), metadata: meta)]
    }

    /// The last-pass settings when they apply (closed vectors cut outside/inside, allowance > 0).
    func effectiveLastPass(tolerance: Double) -> ProfileLastPass? {
        guard let lp = params.lastPass, params.side != .on, lp.allowance > tolerance else { return nil }
        return lp
    }

    /// Orders `chains` (inner loops first) from `start` and cuts each through `passes`. Returns the
    /// material-frame centre of every tab it placed. `inheritedTabs` puts tabs at those centres
    /// (each projected onto the loop within `within`) instead of laying them out afresh.
    @discardableResult
    private func cutLoops(_ chains: [Chain2D], passes: [Double], from start: Vec2, tool: Tool, wasteRegion: WasteSide,
                          sourceStarts: [Vec2], shapeLoops: [[[Vec2]]],
                          inheritedTabs: (points: [Vec2], within: Double)? = nil, context: CAMContext,
                          builder: inout ToolpathBuilder) -> [Vec2] {
        guard !chains.isEmpty else { return [] }
        let tol = context.tolerance
        let startPoint = params.startPoint ?? .nearest
        var ordered = ProfileOrdering.ordered(chains, by: params.order ?? .nearest, from: start, shapeLoops: shapeLoops,
                                              allowReverse: startPoint != .vectorStart, tolerance: tol)
        ordered = ordered.map { StartPoints.rotate($0, to: startPoint, sourceStarts: sourceStarts, tolerance: tol) }
        var manualCenters: [[Double]]?
        if params.tabs.isEnabled, let anchors = params.tabs.manualTabs {
            manualCenters = TabAnchors.centers(for: anchors, loops: ordered.map { ArcLengthChain($0) },
                                               document: context.document, tolerance: tol)
        }
        var placed: [Vec2] = []
        for (i, chain) in ordered.enumerated() {
            var centers = manualCenters?[i]
            if centers == nil, let inherited = inheritedTabs, chain.isClosed {
                let alc = ArcLengthChain(chain)
                centers = inherited.points.compactMap { p in
                    let pr = alc.project(p)
                    return pr.distance <= inherited.within ? pr.s : nil
                }
            }
            placed += cut(chain, passes: passes, tool: tool, wasteRegion: wasteRegion, manualTabs: centers,
                          builder: &builder, tolerance: tol)
        }
        return placed
    }

    /// `manualTabs`: tab centres (loop parameters) for this loop (nil = automatic layout).
    /// Returns the material-frame centre of each tab used.
    private func cut(_ chain: Chain2D, passes: [Double], tool: Tool, wasteRegion: WasteSide, manualTabs: [Double]?,
                     builder: inout ToolpathBuilder, tolerance tol: Double) -> [Vec2] {
        let alc = ArcLengthChain(chain)
        guard alc.length > tol else { return [] }
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
            return []
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
                let isWaste = { (p: Vec2) in wasteRegion.isWaste(p, slack: tol) }
                let inPts = Leads.safeLeadIn(to: alc.point(at: s0), tangent: t0,
                                             waste: wasteRegion.normal(at: alc.point(at: s0), tangent: t0),
                                             settings: params.lead, tolerance: tol, isWaste: isWaste)
                let endP = alc.point(at: pass.endS)
                let outPts = Leads.safeLeadOut(from: endP, tangent: t1,
                                               waste: wasteRegion.normal(at: endP, tangent: t1),
                                               settings: params.lead, tolerance: tol, isWaste: isWaste)
                pts = inPts.map { CutPoint($0, depth: d) } + pts + outPts.map { CutPoint($0, depth: d) }
            }
            // With leads every pass re-enters at the same lead-in, already cut to `prev`.
            builder.cutChain(pts, clearedDepth: useLeads && k > 0 ? prev : 0)
            prev = d
            // Without leads the next pass starts where this one ended (no retract).
            if !useLeads { s0 = pass.endS }
        }
        return tabs?.centers.map { alc.point(at: $0) } ?? []
    }
}

extension CutDirection {
    /// The opposite cutting direction.
    public var reversed: CutDirection { self == .climb ? .conventional : .climb }
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

    /// True when a tool centre at `p` stays on the waste side (no gouge), allowing `slack`
    /// of numerical error at the loop itself.
    public func isWaste(_ p: Vec2, slack: Double) -> Bool {
        if Polygon2D.regionContains(region, p) == wasteInside { return true }
        return region.contains { Polygon2D.distance(from: p, toLoop: $0) <= slack }
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
    /// Miter limit (multiple of the offset) for sharp corners; sharper corners are squared off there.
    public static let sharpMiterLimit = 4.0

    public static func loops(closed: [[Vec2]], side: ProfileSide, offset: Double, direction: CutDirection,
                             tolerance: Double, join: GeomKernel.Join = .round) -> Plan {
        let region = Polygon2D.region(fromLoops: closed)
        var loops: [[Vec2]]
        switch side {
        case .on:
            // Each vector as drawn (no union, so overlapping vectors each get their own cut), oriented
            // the way the region's loops come back: a loop that lies wholly inside an odd number of
            // others is a hole and runs clockwise, so the part is on the same side of travel at a hole
            // as at the outer edge and a ring cut on the line is climb all round. Identical outlines
            // do not count each other, and a loop that only partly overlaps another is not inside it,
            // so duplicates and overlaps are cut like outer loops, as they were before holes were told
            // apart.
            let boxes = closed.map { Rect2(points: $0) }
            loops = closed.indices.map { i in
                let loop = closed[i]
                guard loop.count > 2 else { return loop }
                let depth = closed.indices.filter { j in
                    let other = closed[j], box = boxes[j].insetBy(-tolerance)
                    guard j != i, other.count > 2, box.contains(boxes[i].min), box.contains(boxes[i].max) else { return false }
                    let twin = boxes[i].min.distance(to: boxes[j].min) <= tolerance
                        && boxes[i].max.distance(to: boxes[j].max) <= tolerance
                        && abs(abs(Polygon2D.signedArea(other)) - abs(Polygon2D.signedArea(loop))) <= tolerance
                    if twin { return false }
                    return loop.allSatisfy { v in
                        Polygon2D.contains(other, v) || Polygon2D.distance(from: v, toLoop: other) <= tolerance
                    }
                }.count
                return (Polygon2D.signedArea(loop) < 0) == (depth % 2 == 1) ? loop : loop.reversed()
            }
        case .outside:
            loops = GeomKernel.offset(region, by: max(offset, 0), join: join, arcTolerance: tolerance)
        case .inside:
            loops = GeomKernel.offset(region, by: -max(offset, 0), join: join, arcTolerance: tolerance)
        }
        loops = loops.map { Polygon2D.deduplicated($0, closed: true, tolerance: tolerance * 1e-3) }.filter { $0.count > 2 }
        // Loops have the region on the left (outer CCW, holes CW).
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
