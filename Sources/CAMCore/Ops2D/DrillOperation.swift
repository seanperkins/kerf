import CADCore
import Foundation

/// Drilling: peck drill at the centre of each selected closed vector (circles) / point.
public struct DrillOperation: ToolpathOperation {
    public static let kind = OperationKind.drill
    public var setup: OperationSetup
    public var params: DrillParameters

    public init(setup: OperationSetup, params: DrillParameters = DrillParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-2d): implement.
        throw CAMError.notImplemented("DrillOperation")
    }
}
