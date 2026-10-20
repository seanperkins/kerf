import CADCore
import Foundation

public enum OperationKind: String, Codable, CaseIterable, Sendable {
    case profile, pocket, drill, vcarve, inlay, fluting, texture, relief3D
    // toolpaths-2d additions
    case engrave, chamfer, holeMill, prism

    public var displayName: String {
        switch self {
        case .profile: return "Profile"
        case .pocket: return "Pocket"
        case .drill: return "Drilling"
        case .vcarve: return "V-Carve"
        case .inlay: return "Inlay"
        case .fluting: return "Fluting"
        case .texture: return "Texture"
        case .relief3D: return "3D Relief"
        case .engrave: return "Quick Engrave"
        case .chamfer: return "Chamfer"
        case .holeMill: return "Hole Milling"
        case .prism: return "Prism Carve"
        }
    }
}

public enum CAMError: Error, Equatable, Sendable {
    case notImplemented(String)
    case missingTool(UUID)
    case missingModel(UUID)
    case noGeometry
    /// e.g. an open vector given to a pocket.
    case invalidGeometry(String)
    case invalidParameter(String)
}

/// Common settings of every operation (VCarve's toolpath name / tool / selected vectors).
public struct OperationSetup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Primary tool (library ID).
    public var toolID: UUID
    /// Selected vectors.
    public var shapeIDs: [UUID]

    public init(id: UUID = UUID(), name: String, isEnabled: Bool = true, toolID: UUID, shapeIDs: [UUID] = []) {
        self.id = id; self.name = name; self.isEnabled = isEnabled; self.toolID = toolID; self.shapeIDs = shapeIDs
    }
}

/// Everything a generator needs. Value type: generators are pure functions of it.
public struct CAMContext: Sendable {
    public var document: Document
    public var tools: ToolLibrary
    /// Chordal tolerance for flattening curves (document units).
    public var tolerance: Double

    public init(document: Document, tools: ToolLibrary, tolerance: Double? = nil) {
        self.document = document
        self.tools = tools
        self.tolerance = tolerance ?? (document.units == .inch ? 0.0005 : 0.01)
    }

    public var coords: MachineCoordinates { MachineCoordinates(job: document.job) }
    public var units: LengthUnit { document.units }

    /// Library tool converted to document units.
    public func tool(_ id: UUID) throws -> Tool {
        guard let t = tools.tool(id: id) else { throw CAMError.missingTool(id) }
        return t.converted(to: document.units)
    }

    public func shapes(for setup: OperationSetup) -> [Shape] { document.shapes(ids: setup.shapeIDs) }
}

/// A configured toolpath operation. Implementations live in the workstream folders
/// (Ops2D, OpsVCarve, Ops3D); parameters live in Model/Parameters.
public protocol ToolpathOperation: Codable, Hashable, Sendable {
    static var kind: OperationKind { get }
    var setup: OperationSetup { get set }
    /// Generate toolpaths (one per tool used, in cutting order).
    func generate(in context: CAMContext) throws -> [Toolpath]
}
