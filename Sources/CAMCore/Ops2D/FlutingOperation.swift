import CADCore
import Foundation

/// Fluting: ramped flutes along open vectors (ball nose / V-bit).
public struct FlutingOperation: ToolpathOperation {
    public static let kind = OperationKind.fluting
    public var setup: OperationSetup
    public var params: FlutingParameters

    public init(setup: OperationSetup, params: FlutingParameters = FlutingParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-2d): implement.
        throw CAMError.notImplemented("FlutingOperation")
    }
}
