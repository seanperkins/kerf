import CADCore
import Foundation

/// Chamfer: runs a V-bit along the vector edges so the cone bevels the part edge. The tip follows
/// the vector (or `tipClearance` into the waste) at the depth that gives the requested width.
public struct ChamferOperation: ToolpathOperation {
    public static let kind = OperationKind.chamfer
    public var setup: OperationSetup
    public var params: ChamferParameters

    public init(setup: OperationSetup, params: ChamferParameters = ChamferParameters()) {
        self.setup = setup
        self.params = params
    }

    /// Resolved chamfer size: tip depth, width on the top surface and bevel height on the wall.
    public struct Size: Equatable, Sendable {
        public var depth: Double
        public var width: Double
        public var height: Double
    }

    /// Works out the cut for `tool` (a V-bit or engraving bit with an angle).
    public static func size(tool: Tool, params: ChamferParameters) throws -> Size {
        guard tool.kind == .vBit || tool.kind == .engraving, let angle = tool.angle, angle > 0, angle < 180 else {
            throw CAMError.invalidParameter("Chamfering needs a V-bit")
        }
        let tanHalf = tan(angle / 2 * .pi / 180)
        let tip = tool.tipDiameter / 2
        let e = max(params.tipClearance, 0)
        let depth: Double
        if let d = params.depth {
            depth = d
        } else {
            guard params.width > 0 else { throw CAMError.invalidParameter("Chamfer width must be positive") }
            depth = tool.vDepth(forWidth: 2 * (params.width + e))
        }
        guard depth > params.startDepth else {
            throw CAMError.invalidParameter("The chamfer is no deeper than the start depth")
        }
        // Cone edge distance from the tip centre at the top surface.
        let reach = tip + depth * tanHalf
        guard reach <= tool.radius + 1e-9 else {
            throw CAMError.invalidParameter("The chamfer is wider than the V-bit can cut")
        }
        let width = max(0, reach - e)
        let height = e <= tip ? depth : max(0, depth - (e - tip) / tanHalf)
        return Size(depth: depth, width: width, height: height)
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let size = try Self.size(tool: tool, params: params)
        // The tip runs `tipClearance` off the vector on the waste side: a profile whose offset
        // (tool radius + allowance) equals that clearance.
        var p = ProfileParameters(depth: DepthSettings(startDepth: params.startDepth, cutDepth: size.depth,
                                                       passDepth: params.passDepth),
                                  side: params.side, direction: params.direction)
        p.allowance = max(params.tipClearance, 0) - tool.radius
        var tps = try ProfileOperation(setup: setup, params: p).generate(in: context)
        for i in tps.indices {
            tps[i].kind = .chamfer
            tps[i].metadata["chamfer"] = String(format: "%.4g wide × %.4g high, tip depth %.4g",
                                                size.width, size.height, size.depth)
        }
        return tps
    }
}
