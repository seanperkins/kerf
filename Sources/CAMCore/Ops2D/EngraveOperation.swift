import CADCore
import Foundation

/// Quick engrave: cuts along every selected vector (open or closed) on its centreline at a fixed
/// depth, in passes. A V-bit's groove width follows from the depth.
public struct EngraveOperation: ToolpathOperation {
    public static let kind = OperationKind.engrave
    public var setup: OperationSetup
    public var params: EngraveParameters

    public init(setup: OperationSetup, params: EngraveParameters = EngraveParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        // An "on the line" profile without tabs, ramps or leads is exactly a centreline engrave.
        let profile = ProfileOperation(setup: setup, params: ProfileParameters(depth: params.depth, side: .on,
                                                                               direction: params.direction))
        var tps = try profile.generate(in: context)
        let width = Self.cutWidth(tool: tool, depth: params.depth.cutDepth)
        for i in tps.indices {
            tps[i].kind = .engrave
            tps[i].metadata["cut width"] = String(format: "%.4g", width)
        }
        return tps
    }

    /// Width of the groove a tool cuts at `depth` (V-bit cone, ball radius or full diameter).
    public static func cutWidth(tool: Tool, depth: Double) -> Double {
        let d = max(depth, 0)
        switch tool.kind {
        case .vBit, .engraving:
            return tool.angle == nil ? tool.diameter : tool.vWidth(atDepth: d)
        case .ballNose:
            let r = tool.radius
            return d >= r ? tool.diameter : 2 * (d * (2 * r - d)).squareRoot()
        case .endMill, .drill:
            return tool.diameter
        }
    }
}
