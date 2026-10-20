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
    var clearanceTool: Tool?
    var clearanceStrategy: PocketStrategy = .offset
    var passDepth: Double?
    var tolerance: Double
    var sampleStep: Double

    struct Result {
        /// V-bit strokes grouped by pass, shallowest first.
        var vbitPasses: [[VCarveStroke]]
        /// Clearance-tool strokes grouped by pass (empty without a clearance tool).
        var clearancePasses: [[VCarveStroke]]
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
        var clearance: [[VCarveStroke]] = []
        if unlimitedDepth > limit + 1e-9 {
            let flatRadius = tipRadius + limit * slope
            let flatArea = region.offset(by: -flatRadius, arcTolerance: tolerance)
            if !flatArea.isEmpty {
                if let clr = clearanceTool {
                    vStrokes += VCarveStrokes.loops(flatArea.polygons, depth: bottom)
                    let levels = VCarveStrokes.passLevels(total: bottom, passDepth: clr.stepdown)
                    clearance = levels.map { level in
                        VCarvePocketing.strokes(region: flatArea, toolRadius: clr.radius, stepover: clr.stepover,
                                                strategy: clearanceStrategy, depth: level, arcTolerance: tolerance)
                    }
                    if clearance.allSatisfy(\.isEmpty) {
                        warnings.append("Flat area is too narrow for the clearance tool; the V-bit clears it instead")
                        clearance = []
                    }
                }
                if clearance.isEmpty {
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
        return Result(vbitPasses: vPasses, clearancePasses: clearance.map { VCarveStrokes.ordered($0) },
                      maxDepth: bottom, warnings: warnings)
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

    /// Closed paths of the selected shapes; throws when nothing usable is selected.
    static func closedPaths(_ shapes: [Shape]) throws -> (paths: [Path], skippedOpen: Int) {
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let all = shapes.flatMap(\.paths)
        let closed = all.filter(\.isClosed)
        guard !closed.isEmpty else { throw CAMError.invalidGeometry("V-carving needs closed vectors") }
        return (closed, all.count - closed.count)
    }
}
