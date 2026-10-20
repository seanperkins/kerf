import CADCore
import Foundation

/// Pocket: offset or raster area clearing, optional separate clearance tool.
public struct PocketOperation: ToolpathOperation {
    public static let kind = OperationKind.pocket
    public var setup: OperationSetup
    public var params: PocketParameters

    public init(setup: OperationSetup, params: PocketParameters = PocketParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-2d): implement.
        throw CAMError.notImplemented("PocketOperation")
    }
}
