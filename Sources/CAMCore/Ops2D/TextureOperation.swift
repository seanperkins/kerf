import CADCore
import Foundation

/// Texture: pseudo-random shallow strokes inside the selected boundary (seeded, reproducible).
public struct TextureOperation: ToolpathOperation {
    public static let kind = OperationKind.texture
    public var setup: OperationSetup
    public var params: TextureParameters

    public init(setup: OperationSetup, params: TextureParameters = TextureParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        // TODO(cam-2d): implement.
        throw CAMError.notImplemented("TextureOperation")
    }
}
