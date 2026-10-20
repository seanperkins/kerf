import CADCore
import Foundation

/// Inlay: V-carve female pocket and mirrored male plug with start depth and glue gap.
///
/// Geometry (t = tan(half angle), depths below each board's top):
/// * female: V-carve of the vectors, flat at `pocketDepth` (P) — the wall at depth d sits
///   d·t inside the vector;
/// * male: V-carve of the *complement* (the vectors' bounds grown by `maleBoundaryMargin`,
///   minus the mirrored vectors) with start depth S and total depth P — the plug wall at
///   depth d sits (d − S)·t outside the vector.
/// Flipped into the pocket, the walls coincide when the plug's top is S below the female
/// surface, leaving a bottom gap of P − S (must be ≥ `glueGap`) and the plug board P − S
/// above the female surface.
public struct InlayOperation: ToolpathOperation {
    public static let kind = OperationKind.inlay
    public var setup: OperationSetup
    public var params: InlayParameters

    public init(setup: OperationSetup, params: InlayParameters = InlayParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let p = params
        guard p.pocketDepth > 0 else { throw CAMError.invalidParameter("inlay pocket depth must be positive") }
        guard p.maleStartDepth >= 0, p.glueGap >= 0, p.maleBoundaryMargin >= 0 else {
            throw CAMError.invalidParameter("inlay start depth, glue gap and margin must not be negative")
        }
        guard p.maleStartDepth + p.glueGap <= p.pocketDepth + 1e-9 else {
            throw CAMError.invalidParameter("male start depth + glue gap must not exceed the pocket depth")
        }
        let clearanceDepth = p.effectiveSurfaceClearance
        guard clearanceDepth > 0 else { throw CAMError.invalidParameter("inlay surface clearance must be positive") }
        if p.surfaceClearance != nil, p.part != .female, clearanceDepth >= context.document.job.thickness {
            throw CAMError.invalidParameter("inlay surface clearance must be less than the material thickness")
        }
        let (paths, skipped) = try VCarveEngine.closedPaths(context.shapes(for: setup))
        let vbit = try context.tool(setup.toolID)
        _ = try VCarveEngine.validateVBit(vbit)
        let clearance = try VCarveEngine.clearanceTools(p.clearanceToolIDs, context: context)
        let gap = p.pocketDepth - p.maleStartDepth
        var metadata = ["bottomGap": String(format: "%.4f", gap), "boardGap": String(format: "%.4f", clearanceDepth)]
        if skipped > 0 { metadata["warning"] = "\(skipped) open vector(s) ignored" }

        var out: [Toolpath] = []
        if p.part != .male {
            let region = VCarveRegion(paths: paths, tolerance: context.tolerance, units: context.units)
            guard !region.isEmpty else { throw CAMError.invalidGeometry("selected vectors enclose no area") }
            out += try carve(region, part: "Female", start: 0, depthBelowStart: p.pocketDepth, vbit: vbit,
                             clearance: clearance,
                             context: context, metadata: metadata)
        }
        if p.part != .female {
            out += try carve(maleRegion(paths, context: context), part: "Male", start: p.maleStartDepth,
                             depthBelowStart: clearanceDepth, vbit: vbit, clearance: clearance, context: context,
                             metadata: metadata)
        }
        guard !out.isEmpty else { throw CAMError.invalidGeometry("nothing to carve") }
        return out
    }

    /// Mirrored vectors subtracted from the plug boundary (bounds or outline grown by the
    /// margin, or the material sheet).
    func maleRegion(_ paths: [Path], context: CAMContext) throws -> VCarveRegion {
        let shapeRegion = VCarveRegion(paths: paths, tolerance: context.tolerance, units: context.units)
        guard !shapeRegion.isEmpty else { throw CAMError.invalidGeometry("selected vectors enclose no area") }
        var polys = shapeRegion.polygons
        let b = shapeRegion.bounds
        if params.mirrorMale {
            let m = Transform2D.mirror(horizontalAxis: false, about: b.center)
            polys = polys.map { Array($0.map(m.apply).reversed()) }
        }
        let precision = Int32(log10(shapeRegion.scale).rounded())
        let frame: [[Vec2]]
        switch params.plugBoundary {
        case .boundaryOffset:
            let g = b.insetBy(-params.maleBoundaryMargin)
            frame = [[g.min, Vec2(g.max.x, g.min.y), g.max, Vec2(g.min.x, g.max.y)]]
        case .vectorOffset:
            let mirrored = VCarveRegion(polygons: polys, scale: shapeRegion.scale)
            // Outer loops only: counters (the hole of an "O") are waste on the plug too.
            frame = mirrored.offset(by: params.maleBoundaryMargin, arcTolerance: context.tolerance).polygons
                .filter { VCarveRegion(polygons: [$0], scale: shapeRegion.scale).area > 0 }
        case .sheetLimits:
            let job = context.document.job
            frame = [[Vec2(0, 0), Vec2(job.width, 0), Vec2(job.width, job.height), Vec2(0, job.height)]]
        }
        let complement = GeomKernel.boolean(.difference, subject: frame, clip: polys, fillRule: .evenOdd,
                                            precision: precision)
        let region = VCarveRegion(polygons: complement, scale: shapeRegion.scale)
        guard !region.isEmpty else { throw CAMError.invalidGeometry("male boundary margin leaves nothing to carve") }
        return region
    }

    private func carve(_ region: VCarveRegion, part: String, start: Double, depthBelowStart: Double, vbit: Tool,
                       clearance: [Tool],
                       context: CAMContext, metadata: [String: String]) throws -> [Toolpath] {
        var engine = VCarveEngine(region: region, vbit: vbit, context: context)
        engine.startDepth = start
        engine.flatDepth = depthBelowStart
        engine.clearanceTools = clearance
        engine.cornerSharpen = [false] + params.extraClearanceTools.map(\.cornerSharpen)
        let result = try engine.run()
        var meta = metadata
        meta["part"] = part.lowercased()
        meta["maxDepth"] = String(format: "%.4f", result.maxDepth)
        if !result.warnings.isEmpty {
            meta["warning"] = ([meta["warning"]].compactMap { $0 } + result.warnings).joined(separator: "; ")
        }
        return VCarveEngine.toolpaths(name: "\(setup.name) \(part)", operationID: setup.id, kind: Self.kind,
                                      vbit: vbit, result: result, context: context, metadata: meta)
    }
}
