import CADCore
import Foundation

/// 3D relief: heightmap from STL, z-level roughing + raster finishing (ball/flat/V tool).
///
/// Produces up to two toolpaths in cutting order: roughing (flat end mill, leaves
/// `roughing.allowance`) then finishing (primary tool, drop-cutter raster). The machined area
/// is the union of the closed boundary vectors, or the model's footprint when there are none;
/// the tool centre stays inside it. Outside the model's triangles the surface is the model's
/// bottom plane (`PlacedModel.depth`).
public struct Relief3DOperation: ToolpathOperation {
    public static let kind = OperationKind.relief3D
    public var setup: OperationSetup
    public var params: Relief3DParameters

    public init(setup: OperationSetup, params: Relief3DParameters) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        guard let model = context.document.model(id: params.modelID) else { throw CAMError.missingModel(params.modelID) }
        guard model.mesh.triangleCount > 0 else { throw CAMError.noGeometry }
        guard params.roughing.isEnabled || params.finishing.isEnabled else {
            throw CAMError.invalidParameter("Enable roughing and/or finishing")
        }
        let finishTool = try context.tool(setup.toolID)
        let roughTool = try context.tool(params.roughing.toolID ?? setup.toolID)
        if params.roughing.isEnabled, roughTool.kind != .endMill {
            throw CAMError.invalidParameter("3D roughing needs an end mill")
        }

        let boundaryShapes = context.document.shapes(ids: params.boundaryShapeIDs)
        var region = ReliefRegion.polygons(of: boundaryShapes, tolerance: context.tolerance)
        if region.isEmpty { region = [ReliefRegion.rectangle(model.footprint)] }
        let regionBounds = Rect2(points: region.flatMap { $0 })
        guard !regionBounds.isEmpty, regionBounds.width > 0 || regionBounds.height > 0 else { throw CAMError.noGeometry }

        let reach = max(finishTool.radius, roughTool.radius + max(0, params.roughing.allowance))
        let area = regionBounds.insetBy(-(reach + 2 * params.resolution))
        var metadata: [String: String] = [:]
        let cellSize = Self.cellSize(requested: params.resolution, area: area)
        if cellSize > params.resolution * 1.0001 {
            metadata["warning"] = String(format: "Heightmap resolution coarsened to %.4g", cellSize)
        }
        let map = try ReliefHeightmap.rasterize(model, over: area, cellSize: cellSize)
        if map.maxDepth > context.document.job.thickness + 1e-9 {
            metadata["warning"] = "Model is deeper than the material thickness"
        }
        let clearance = context.units == .inch ? 0.04 : 1.0
        let coords = context.coords
        var result: [Toolpath] = []

        if params.roughing.isEnabled {
            let moves = ReliefRoughing.moves(map: map, region: region, tool: roughTool,
                                             allowance: params.roughing.allowance,
                                             passDepth: params.roughing.passDepth, strategy: params.roughing.strategy,
                                             coords: coords, clearance: clearance, tolerance: context.tolerance)
            if !moves.isEmpty {
                var meta = metadata
                meta["pass"] = "roughing"
                result.append(Toolpath(name: "\(setup.name) (Roughing)", operationID: setup.id, kind: .relief3D,
                                       tool: roughTool, moves: moves, metadata: meta))
            }
        }
        if params.finishing.isEnabled {
            let stepover = max(params.finishing.stepover ?? finishTool.stepover, 1e-4)
            let moves = ReliefFinishing.moves(map: map, region: region, tool: finishTool, stepover: stepover,
                                              angle: params.finishing.angle, coords: coords,
                                              tolerance: context.tolerance, clearance: clearance)
            if !moves.isEmpty {
                var meta = metadata
                meta["pass"] = "finishing"
                result.append(Toolpath(name: "\(setup.name) (Finishing)", operationID: setup.id, kind: .relief3D,
                                       tool: finishTool, moves: moves, metadata: meta))
            }
        }
        guard !result.isEmpty else { throw CAMError.noGeometry }
        return result
    }

    /// Requested cell size, coarsened if needed so the grid stays well under the cell cap.
    static func cellSize(requested: Double, area: Rect2) -> Double {
        let r = max(requested, 1e-6)
        let budget = Double(ReliefHeightmap.maxCells) / 2
        let needed = (area.width * area.height / budget).squareRoot()
        return max(r, needed)
    }
}
