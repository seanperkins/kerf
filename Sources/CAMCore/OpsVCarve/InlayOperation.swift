import CADCore
import Foundation

/// Inlay: V-carve female pocket and mirrored male plug with start depth and glue gap.
public struct InlayOperation: ToolpathOperation {
    public static let kind = OperationKind.inlay
    public var setup: OperationSetup
    public var params: InlayParameters

    public init(setup: OperationSetup, params: InlayParameters = InlayParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-vcarve): implement.
        throw CAMError.notImplemented("InlayOperation")
    }
}
