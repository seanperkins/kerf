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

    /// Depth below the material top where the operation starts cutting because an earlier operation
    /// removed the material above it (0 = the top); the flute check measures the cut from there.
    /// Only a start depth with that meaning counts: moulding's is an offset into solid material,
    /// the inlay's male start depth is where the plug's cone starts in solid stock, and the rest
    /// have none.
    private var startDepth: Double {
        switch self {
        case .profile(let o): o.params.depth.startDepth
        case .pocket(let o): o.params.depth.startDepth
        case .fluting(let o): o.params.depth.startDepth
        case .engrave(let o): o.params.depth.startDepth
        case .drill(let o): o.params.startDepth
        case .holeMill(let o): o.params.startDepth
        case .vcarve(let o): o.params.startDepth
        case .photoVCarve(let o): o.params.startDepth
        case .chamfer(let o): o.params.startDepth
        case .inlay, .texture, .relief3D, .prism, .merge, .straightInlay, .moulding: 0
        }
    }
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
        // The material above the operation's start depth is already gone; the flute check
        // measures the cut from there.
        let cleared = startDepth
        if cleared > 0 { for i in tps.indices { tps[i].clearedDepth = cleared } }
        if let modelID = setup.projectOntoModelID, kind != .relief3D {
            // Projection drops every point to the carved surface, which an earlier operation cut
            // away: what the tool enters is the cut it was given, so the drop counts as cleared.
            let before = tps.map(\.minCutZ)
            tps = try ReliefProjection.project(tps, ontoModel: modelID, in: ctx)
            for i in tps.indices {
                if let b = before[i], let a = tps[i].minCutZ, a < b { tps[i].clearedDepth = (tps[i].clearedDepth ?? 0) + (b - a) }
            }
        }
        tps = Self.liftOverKeepOutZones(tps, in: ctx)
        // A merge's children were noted when they were generated (merges are flattened one level,
        // so a merge never holds a merge).
        return kind == .merge ? tps : Self.notingCutsBeyondTheFlute(tps, in: ctx)
    }

    /// Adds a warning to every toolpath that cuts deeper than its tool's flute length (last, so it
    /// sees the final Z of array copies and projection). The export check flags the same cut as
    /// an error; this tells the operator at design time, with both numbers.
    static func notingCutsBeyondTheFlute(_ tps: [Toolpath], in ctx: CAMContext) -> [Toolpath] {
        tps.map { tp in
            guard let over = tp.cutBeyondFlute(coords: ctx.coords, units: ctx.units, tolerance: ctx.tolerance) else { return tp }
            var out = tp
            out.metadata["warning"] = out.metadata["warning"].map { "\($0); \(over.note)" } ?? over.note
            return out
        }
    }

    /// Re-routes over keep-out zones marked "lift over" (after projection, so it sees the final Z).
    static func liftOverKeepOutZones(_ tps: [Toolpath], in ctx: CAMContext) -> [Toolpath] {
        guard let zones = ctx.document.keepOutZones, zones.contains(where: { $0.liftOver == true }) else { return tps }
        let margin = ctx.units == .inch ? 0.05 : 1.0 // same clearance the export check uses
        return KeepOutAvoidance.apply(tps, zones: zones, coords: ctx.coords, margin: margin,
                                      tolerance: ctx.tolerance).toolpaths
    }
}
