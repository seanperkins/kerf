import CADCore
import Foundation

/// 3D relief: heightmap from STL, z-level roughing + raster finishing (ball/flat/V tool).
public struct Relief3DOperation: ToolpathOperation {
    public static let kind = OperationKind.relief3D
    public var setup: OperationSetup
    public var params: Relief3DParameters

    public init(setup: OperationSetup, params: Relief3DParameters) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-3d): implement.
        throw CAMError.notImplemented("Relief3DOperation")
    }
}
