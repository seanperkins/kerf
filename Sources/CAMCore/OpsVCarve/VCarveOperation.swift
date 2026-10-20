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
        // TODO(cam-vcarve): implement.
        throw CAMError.notImplemented("VCarveOperation")
    }
}
