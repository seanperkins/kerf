import CADCore
import CAMCore
import Foundation

extension AnyOperation {
    /// Read/write access to the common setup regardless of the concrete operation.
    var editableSetup: OperationSetup {
        get { setup }
        set {
            switch self {
            case .profile(var o): o.setup = newValue; self = .profile(o)
            case .pocket(var o): o.setup = newValue; self = .pocket(o)
            case .drill(var o): o.setup = newValue; self = .drill(o)
            case .vcarve(var o): o.setup = newValue; self = .vcarve(o)
            case .inlay(var o): o.setup = newValue; self = .inlay(o)
            case .fluting(var o): o.setup = newValue; self = .fluting(o)
            case .texture(var o): o.setup = newValue; self = .texture(o)
            case .relief3D(var o): o.setup = newValue; self = .relief3D(o)
            case .engrave(var o): o.setup = newValue; self = .engrave(o)
            case .chamfer(var o): o.setup = newValue; self = .chamfer(o)
            case .holeMill(var o): o.setup = newValue; self = .holeMill(o)
            }
        }
    }

    /// Every library tool the operation references (primary + clearance/roughing tools).
    var referencedToolIDs: [UUID] {
        var ids = [setup.toolID]
        switch self {
        case .pocket(let o): ids += o.params.clearanceTools
        case .vcarve(let o): if let c = o.params.flatClearanceToolID { ids.append(c) }
        case .inlay(let o): if let c = o.params.flatClearanceToolID { ids.append(c) }
        case .relief3D(let o): if let c = o.params.roughing.toolID { ids.append(c) }
        default: break
        }
        return ids
    }
}

/// Creates operations with sensible, unit-aware defaults (the parameter structs' defaults are
/// in inches; millimetre documents get them scaled by 25.4).
enum OperationFactory {
    /// Kinds offered in the "New toolpath" menu, in VCarve-like order.
    static let menuKinds: [OperationKind] = [.profile, .pocket, .drill, .holeMill, .engrave, .chamfer, .vcarve, .inlay, .fluting, .texture, .relief3D]

    /// Title in the "New toolpath" menus (Inlay opens the pocket + plug wizard).
    static func menuTitle(_ kind: OperationKind) -> String {
        kind == .inlay ? "Inlay (Pocket + Plug)…" : kind.displayName
    }

    /// Label of the primary tool picker for an operation kind.
    static func primaryToolTitle(_ kind: OperationKind) -> String {
        switch kind {
        case .pocket: return "Finish tool"
        case .vcarve, .inlay, .chamfer: return "V-bit"
        case .drill: return "Drill"
        case .relief3D: return "Finishing tool"
        default: return "Tool"
        }
    }

    /// Preferred tool kinds for an operation (first match in the library wins).
    static func preferredToolKinds(for kind: OperationKind) -> [ToolKind] {
        switch kind {
        case .profile, .pocket, .holeMill: return [.endMill, .ballNose]
        case .drill: return [.drill, .endMill]
        case .vcarve, .inlay, .chamfer: return [.vBit, .engraving]
        case .engrave: return [.engraving, .vBit, .ballNose, .endMill]
        case .fluting: return [.ballNose, .vBit, .endMill]
        case .texture: return [.ballNose, .vBit]
        case .relief3D: return [.ballNose, .endMill]
        }
    }

    static func defaultTool(for kind: OperationKind, in library: ToolLibrary) -> Tool? {
        for k in preferredToolKinds(for: kind) {
            if let t = library.tools.first(where: { $0.kind == k }) { return t }
        }
        return library.tools.first
    }

    /// "Profile 1", "Profile 2"… unique among `existing`.
    static func defaultName(for kind: OperationKind, existing: [AnyOperation]) -> String {
        let names = Set(existing.map(\.setup.name))
        var n = existing.filter { $0.kind == kind }.count + 1
        while names.contains("\(kind.displayName) \(n)") { n += 1 }
        return "\(kind.displayName) \(n)"
    }

    /// Builds a new operation. Returns nil only for a 3D relief without any placed model.
    static func make(kind: OperationKind, project: KerfProject, library: ToolLibrary,
                     shapeIDs: [UUID]) -> AnyOperation? {
        let doc = project.document
        let f = LengthUnit.inch.factor(to: doc.units)
        let toolID = defaultTool(for: kind, in: library)?.id ?? UUID()
        let setup = OperationSetup(name: defaultName(for: kind, existing: project.operations),
                                   toolID: toolID, shapeIDs: shapeIDs)
        let thickness = doc.job.thickness
        switch kind {
        case .profile:
            var p = ProfileParameters().scaled(by: f)
            p.depth.cutDepth = thickness
            return .profile(ProfileOperation(setup: setup, params: p))
        case .pocket:
            var p = PocketParameters().scaled(by: f)
            p.depth.cutDepth = min(p.depth.cutDepth, thickness)
            return .pocket(PocketOperation(setup: setup, params: p))
        case .drill:
            var p = DrillParameters().scaled(by: f)
            p.cutDepth = min(p.cutDepth, thickness)
            return .drill(DrillOperation(setup: setup, params: p))
        case .vcarve:
            return .vcarve(VCarveOperation(setup: setup, params: VCarveParameters().scaled(by: f)))
        case .inlay:
            return .inlay(InlayOperation(setup: setup, params: InlayParameters().scaled(by: f)))
        case .fluting:
            return .fluting(FlutingOperation(setup: setup, params: FlutingParameters().scaled(by: f)))
        case .texture:
            return .texture(TextureOperation(setup: setup, params: TextureParameters().scaled(by: f)))
        case .engrave:
            return .engrave(EngraveOperation(setup: setup, params: EngraveParameters().scaled(by: f)))
        case .chamfer:
            return .chamfer(ChamferOperation(setup: setup, params: ChamferParameters().scaled(by: f)))
        case .holeMill:
            var p = HoleMillParameters().scaled(by: f)
            p.cutDepth = min(p.cutDepth, thickness)
            return .holeMill(HoleMillOperation(setup: setup, params: p))
        case .relief3D:
            guard let model = doc.models.first else { return nil }
            var s = setup
            s.shapeIDs = []
            var p = Relief3DParameters(modelID: model.id, boundaryShapeIDs: shapeIDs).scaled(by: f)
            // Roughing needs an end mill; the primary (finishing) tool is usually a ball nose.
            if library.tool(id: toolID)?.kind != .endMill {
                if let mill = library.tools.first(where: { $0.kind == .endMill }) {
                    p.roughing.toolID = mill.id
                } else {
                    p.roughing.isEnabled = false
                }
            }
            return .relief3D(Relief3DOperation(setup: s, params: p))
        }
    }
}
