import CADCore
import Foundation

/// Type-erased, Codable operation for storing heterogeneous operations in a project.
public enum AnyOperation: Codable, Hashable, Identifiable, Sendable {
    case profile(ProfileOperation)
    case pocket(PocketOperation)
    case drill(DrillOperation)
    case vcarve(VCarveOperation)
    case inlay(InlayOperation)
    case fluting(FlutingOperation)
    case texture(TextureOperation)
    case relief3D(Relief3DOperation)
    case photoVCarve(PhotoVCarveOperation)
    case engrave(EngraveOperation)
    case chamfer(ChamferOperation)
    case holeMill(HoleMillOperation)
    case prism(PrismOperation)
    case merge(MergeOperation)
    case straightInlay(StraightInlayOperation)
    case moulding(MouldingOperation)

    public var operation: any ToolpathOperation {
        switch self {
        case .profile(let o): return o
        case .pocket(let o): return o
        case .drill(let o): return o
        case .vcarve(let o): return o
        case .inlay(let o): return o
        case .fluting(let o): return o
        case .texture(let o): return o
        case .relief3D(let o): return o
        case .photoVCarve(let o): return o
        case .engrave(let o): return o
        case .chamfer(let o): return o
        case .holeMill(let o): return o
        case .prism(let o): return o
        case .merge(let o): return o
        case .straightInlay(let o): return o
        case .moulding(let o): return o
        }
    }

    public var kind: OperationKind { type(of: operation).kind }
    public var setup: OperationSetup { operation.setup }
    public var id: UUID { setup.id }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        var ctx = context
        if let o = setup.toolOverride, !o.isEmpty { ctx.toolOverrides[setup.toolID] = o }
        var tps = try operation.generate(in: ctx)
        // Array copies first, so each copy is projected onto the model where it actually lands.
        if let array = setup.arrayCopy {
            tps = ToolpathArray.apply(array, to: tps, coords: ctx.coords, tolerance: ctx.tolerance)
        }
        guard let modelID = setup.projectOntoModelID, kind != .relief3D else { return tps }
        return try ReliefProjection.project(tps, ontoModel: modelID, in: ctx)
    }
}
