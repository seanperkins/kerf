import CADCore
import Foundation

/// V-Carve: medial-axis carving with depth = inscribed radius / tan(angle/2), optional flat depth + clearance tool.
public struct VCarveOperation: ToolpathOperation {
    public static let kind = OperationKind.vcarve
    public var setup: OperationSetup
    public var params: VCarveParameters

    public init(setup: OperationSetup, params: VCarveParameters = VCarveParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let (paths, open) = try VCarveEngine.splitPaths(context.shapes(for: setup))
        let engraveDepth = params.openVectorDepth
        if let d = engraveDepth, d <= 0 { throw CAMError.invalidParameter("open vector engraving depth must be positive") }
        let engraving = engraveDepth == nil ? [] : open
        guard !paths.isEmpty || !engraving.isEmpty else {
            throw CAMError.invalidGeometry(open.isEmpty ? "V-carving needs closed vectors"
                                           : "V-carving needs closed vectors (or turn on open vector engraving)")
        }
        let skipped = open.count - engraving.count
        let vbit = try context.tool(setup.toolID)
        var engine = VCarveEngine(region: VCarveRegion(paths: paths, tolerance: context.tolerance, units: context.units),
                                  vbit: vbit, context: context)
        guard !engine.region.isEmpty || !engraving.isEmpty else {
            throw CAMError.invalidGeometry("selected vectors enclose no area")
        }
        if let d = engraveDepth {
            engine.engraveStrokes = engraving.compactMap {
                VCarveEngraving.stroke($0, startDepth: params.startDepth, depth: d, taper: params.openVectorTaper,
                                       tolerance: context.tolerance, step: engine.sampleStep)
            }
        }
        if params.useVectorStartPoints || params.useSelectionOrder {
            engine.ordering = VCarveOrdering(shapes: context.shapes(for: setup), useStartPoints: params.useVectorStartPoints,
                                             useSelectionOrder: params.useSelectionOrder, tolerance: context.tolerance,
                                             units: context.units)
        }
        engine.startDepth = params.startDepth
        engine.flatDepth = params.flatDepth
        engine.clearanceTools = params.flatDepth == nil
            ? [] : try VCarveEngine.clearanceTools(params.clearanceTools.map(\.toolID), context: context)
        engine.cornerSharpen = params.clearanceTools.map(\.cornerSharpen)
        engine.clearanceStrategy = params.flatClearanceStrategy
        engine.passDepth = params.passDepth
        let result = try engine.run()

        var metadata = ["maxDepth": String(format: "%.4f", result.maxDepth)]
        var warnings = result.warnings
        if skipped > 0 { warnings.append("\(skipped) open vector(s) ignored") }
        if !warnings.isEmpty { metadata["warning"] = warnings.joined(separator: "; ") }

        let out = VCarveEngine.toolpaths(name: setup.name, operationID: setup.id, kind: Self.kind, vbit: vbit,
                                         result: result, context: context, metadata: metadata)
        guard !out.isEmpty else { throw CAMError.invalidGeometry("nothing to carve") }
        return out
    }
}
