import CADCore
import Foundation

/// Profile: offset outside/inside/on the vector, multi-pass, climb/conventional, tabs, ramps, lead-in, allowance.
public struct ProfileOperation: ToolpathOperation {
    public static let kind = OperationKind.profile
    public var setup: OperationSetup
    public var params: ProfileParameters

    public init(setup: OperationSetup, params: ProfileParameters = ProfileParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-2d): implement.
        throw CAMError.notImplemented("ProfileOperation")
    }
}
