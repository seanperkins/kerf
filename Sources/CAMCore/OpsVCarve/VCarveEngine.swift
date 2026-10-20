import CADCore
import Foundation

/// The V-carve calculation shared by `VCarveOperation` and `InlayOperation`.
///
/// Depth at a medial-axis point with inscribed radius r:
///     depth = startDepth + min(max(0, r - tipRadius) / tan(angle/2), limit)
/// where `limit` = min(flatDepth, the bit's full cutting depth). `flatDepth` is measured
/// below `startDepth`. Where the limit bites, the "flat area" (points at least
/// tipRadius + limit·tan(angle/2) from the boundary) is cleared at the limit depth — by the
/// clearance tool when given (plus a V-bit trace of the flat area's boundary to cut crisp
/// walls), otherwise by V-bit offset/raster passes.
struct VCarveEngine {
    var region: VCarveRegion
    var vbit: Tool
    var startDepth: Double = 0
    var flatDepth: Double?
    /// Flat-area clearance tools in cutting order; each later tool only machines the part of
    /// the flat area the earlier ones could not reach.
    var clearanceTools: [Tool] = []
    /// Per clearance tool (same indices): lift into corners it cannot reach at the flat depth.
    var cornerSharpen: [Bool] = []
    var clearanceStrategy: PocketStrategy = .offset
    var passDepth: Double?
    var tolerance: Double
    var sampleStep: Double

    struct Result {
        /// V-bit strokes grouped by pass, shallowest first.
        var vbitPasses: [[VCarveStroke]]
        /// Per clearance tool (in cutting order), strokes grouped by pass. Tools that found
        /// nothing to cut are left out.
        var clearance: [(tool: Tool, passes: [[VCarveStroke]])]
        var maxDepth: Double
        var warnings: [String]
    }

    static func validateVBit(_ tool: Tool) throws -> Double {
        guard let angle = tool.angle, angle > 0, angle < 180 else {
            throw CAMError.invalidParameter("V-carve needs a V-bit or engraving tool with an included angle (\(tool.name))")
        }
        return tan(angle / 2 * .pi / 180)
    }

    func run() throws -> Result {
        let slope = try Self.validateVBit(vbit)
        guard startDepth >= 0 else { throw CAMError.invalidParameter("start depth must not be negative") }
        if let f = flatDepth, f <= 0 { throw CAMError.invalidParameter("flat depth must be positive") }
        let tipRadius = max(0, vbit.tipDiameter / 2)
        let toolLimit = max(0, vbit.radius - tipRadius) / slope
        let limit = min(flatDepth ?? .infinity, toolLimit)
        var warnings: [String] = []

        let axis = VCarveMedialAxis(region: region, sampleStep: sampleStep)
        let widest = axis.chains.joined().map(\.radius).max() ?? 0
        let unlimitedDepth = max(0, widest - tipRadius) / slope
        if flatDepth == nil || toolLimit < flatDepth! - 1e-9, unlimitedDepth > toolLimit + 1e-9 {
            warnings.append(String(format: "Vectors are wider than the V-bit; depth limited to %.4f", startDepth + toolLimit))
        }
        func depth(_ r: Double) -> Double { startDepth + min(max(0, r - tipRadius) / slope, limit) }
        var vStrokes = axis.chains.map { chain in
            VCarveStroke(points: chain.map { Vec3($0.position, z: depth($0.radius)) }, isClosed: false)
        }

        let bottom = startDepth + min(limit, unlimitedDepth)
        var clearance: [(tool: Tool, passes: [[VCarveStroke]])] = []
        if unlimitedDepth > limit + 1e-9 {
            let flatRadius = tipRadius + limit * slope
            let flatArea = region.offset(by: -flatRadius, arcTolerance: tolerance)
            if !flatArea.isEmpty {
                clearance = clearFlatArea(flatArea, bottom: bottom, vSlope: slope, axis: axis, warnings: &warnings)
                if !clearance.isEmpty {
                    vStrokes += VCarveStrokes.loops(flatArea.polygons, depth: bottom)
                } else {
                    vStrokes += VCarvePocketing.strokes(region: flatArea, toolRadius: 0, stepover: vbit.stepover,
                                                        strategy: clearanceStrategy, depth: bottom, arcTolerance: tolerance)
                }
            }
        }

        let levels = VCarveStrokes.passLevels(total: bottom, passDepth: passDepth)
        let vPasses = VCarveStrokes.multiPass(vStrokes, levels: levels).map { pass in
            VCarveStrokes.ordered(pass.map {
                VCarveStroke(points: VCarveStrokes.simplified($0.points, tolerance: tolerance), isClosed: $0.isClosed)
            })
        }
        return Result(vbitPasses: vPasses,
                      clearance: clearance.map { ($0.tool, $0.passes.map { VCarveStrokes.ordered($0) }) },
                      maxDepth: bottom, warnings: warnings)
    }

    /// Clears the flat area with the clearance tools in order (rest machining after the first).
    private func clearFlatArea(_ flatArea: VCarveRegion, bottom: Double, vSlope: Double, axis: VCarveMedialAxis,
                               warnings: inout [String]) -> [(tool: Tool, passes: [[VCarveStroke]])] {
        guard !clearanceTools.isEmpty else { return [] }
        let flatBelowStart = bottom - startDepth
        var out: [(tool: Tool, passes: [[VCarveStroke]])] = []
        var cleared: VCarveRegion?
        for (index, clr) in clearanceTools.enumerated() {
            let reach = Self.wallClearance(of: clr, flatDepth: flatBelowStart, vSlope: vSlope)
            let foot = Self.floorRadius(of: clr)
            var centres = flatArea.offset(by: -reach, arcTolerance: tolerance)
            if let done = cleared {
                let rest = flatArea.combined(.difference, with: done)
                // Slivers thinner than the grid are not worth a tool change.
                guard rest.area > 1e-4 * max(flatArea.area, 1e-12) else { break }
                centres = centres.combined(.intersection, with: rest.offset(by: foot, arcTolerance: tolerance))
            }
            let levels = VCarveStrokes.passLevels(total: bottom, passDepth: clr.stepdown)
            let step = clr.stepover > 0 ? min(clr.stepover, 1.9 * foot) : foot
            let passes = levels.map { level in
                VCarvePocketing.strokes(region: centres, toolRadius: 0, stepover: step,
                                        strategy: clearanceStrategy, depth: level, arcTolerance: tolerance)
            }
            let swept = centres.offset(by: foot, arcTolerance: tolerance)
            let clearedNow = cleared.map { $0.combined(.union, with: swept) } ?? swept
            var sharpen: [VCarveStroke] = []
            if index < cornerSharpen.count, cornerSharpen[index] {
                sharpen = Self.cornerStrokes(axis: axis, tool: clr, vSlope: vSlope, startDepth: startDepth,
                                             bottom: bottom, flatArea: flatArea, cleared: clearedNow)
                if sharpen.isEmpty, clr.angle == nil {
                    warnings.append("Corner sharpening needs a tapered (V or engraving) tool; ignored for \(clr.name)")
                }
            }
            var all = passes
            if !sharpen.isEmpty { all += VCarveStrokes.multiPass(sharpen, levels: levels) }
            guard !all.allSatisfy(\.isEmpty) else {
                warnings.append(out.isEmpty
                    ? "Flat area is too narrow for the clearance tool; the V-bit clears it instead"
                    : "\(clr.name) has no remaining flat area to clear")
                continue
            }
            out.append((clr, all))
            cleared = clearedNow
        }
        return out
    }

    /// Corner sharpening: the medial-axis runs inside the flat area that no clearance tool has
    /// swept, cut with a tapered tool lifted so it never touches the V walls. With the tool's
    /// centre R from the vectors, its cone (tip radius rt, slope tT) stays inside the walls
    /// (slope tV, measured from the start depth) when depth ≤ (R − rt) / max(tT, tV).
    static func cornerStrokes(axis: VCarveMedialAxis, tool: Tool, vSlope: Double, startDepth: Double, bottom: Double,
                              flatArea: VCarveRegion, cleared: VCarveRegion) -> [VCarveStroke] {
        guard let angle = tool.angle, angle > 0, angle < 180, tool.kind == .vBit || tool.kind == .engraving else { return [] }
        let toolSlope = tan(angle / 2 * .pi / 180)
        let rt = max(0, tool.tipDiameter / 2)
        let grow = flatArea.offset(by: 1e-3 * max(1, rt), arcTolerance: 1e-4)
        var out: [VCarveStroke] = []
        for chain in axis.chains {
            var run: [Vec3] = []
            func flush() {
                if run.count >= 2 { out.append(VCarveStroke(points: run, isClosed: false)) }
                run = []
            }
            for p in chain {
                let lift = (p.radius - rt) / max(toolSlope, vSlope)
                let wanted = lift > 1e-6 && grow.contains(p.position) && !cleared.contains(p.position)
                if wanted {
                    run.append(Vec3(p.position, z: startDepth + min(lift, bottom - startDepth)))
                } else {
                    flush()
                }
            }
            flush()
        }
        return out
    }

    /// How far a clearance tool's centre must stay inside the flat area so no part of it cuts
    /// the V-carved walls: the radius for cylindrical tools; for tapered (V / engraving) tools
    /// the tip radius plus whatever the taper gains on the walls over the flat depth.
    static func wallClearance(of tool: Tool, flatDepth: Double, vSlope: Double) -> Double {
        guard let angle = tool.angle, angle > 0, angle < 180, tool.kind == .vBit || tool.kind == .engraving else {
            return tool.radius
        }
        let toolSlope = tan(angle / 2 * .pi / 180)
        return min(tool.radius, max(0, tool.tipDiameter / 2) + flatDepth * max(0, toolSlope - vSlope))
    }

    /// Radius of the flat floor a clearance tool leaves at its tip.
    static func floorRadius(of tool: Tool) -> Double {
        if tool.angle != nil, tool.kind == .vBit || tool.kind == .engraving { return max(tool.tipDiameter / 2, 1e-4) }
        return tool.radius
    }
}

extension VCarveEngine {
    /// Engine configured from a CAM context's units and tolerance.
    init(region: VCarveRegion, vbit: Tool, context: CAMContext) {
        self.init(region: region, vbit: vbit, tolerance: context.tolerance,
                  sampleStep: context.units == .inch ? 0.01 : 0.25)
    }

    static func linkTolerance(_ context: CAMContext) -> Double { context.units == .inch ? 0.002 : 0.05 }

    /// One toolpath from pass-grouped strokes, or nil when there is nothing to cut.
    static func toolpath(name: String, operationID: UUID, kind: OperationKind, tool: Tool,
                         passes: [[VCarveStroke]], context: CAMContext, metadata: [String: String]) -> Toolpath? {
        let strokes = passes.joined().filter { $0.points.count >= 2 }
        guard !strokes.isEmpty else { return nil }
        var writer = VCarveMoveWriter(coords: context.coords, feed: tool.feedRate, plunge: tool.plungeRate,
                                      linkTolerance: linkTolerance(context))
        for s in strokes { writer.cut(s) }
        return Toolpath(name: name, operationID: operationID, kind: kind, tool: tool,
                        moves: writer.finish(), metadata: metadata)
    }

    /// Clearance toolpaths (first named "(flat clearance)", later ones numbered) then the V-bit.
    static func toolpaths(name: String, operationID: UUID, kind: OperationKind, vbit: Tool, result: Result,
                          context: CAMContext, metadata: [String: String]) -> [Toolpath] {
        var out: [Toolpath] = []
        for (i, c) in result.clearance.enumerated() {
            let label = i == 0 ? "\(name) (flat clearance)" : "\(name) (flat clearance \(i + 1))"
            if let tp = toolpath(name: label, operationID: operationID, kind: kind, tool: c.tool, passes: c.passes,
                                 context: context, metadata: metadata) {
                out.append(tp)
            }
        }
        if let tp = toolpath(name: name, operationID: operationID, kind: kind, tool: vbit, passes: result.vbitPasses,
                             context: context, metadata: metadata) {
            out.append(tp)
        }
        return out
    }

    /// Clearance tools from the library (converted to document units), in cutting order.
    static func clearanceTools(_ ids: [UUID], context: CAMContext) throws -> [Tool] {
        try ids.map { try context.tool($0) }
    }

    /// Closed paths of the selected shapes; throws when nothing usable is selected.
    static func closedPaths(_ shapes: [Shape]) throws -> (paths: [Path], skippedOpen: Int) {
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let all = shapes.flatMap(\.paths)
        let closed = all.filter(\.isClosed)
        guard !closed.isEmpty else { throw CAMError.invalidGeometry("V-carving needs closed vectors") }
        return (closed, all.count - closed.count)
    }
}
