import CADCore
import Foundation

/// A native `.loftline` file: the design plus its toolpath operations (JSON).
public struct LoftLineProject: Codable, Hashable, Sendable {
    public static let fileExtension = "loftline"
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var document: Document
    public var operations: [AnyOperation]
    /// Snapshot of tools referenced by operations so the file opens on any machine.
    public var tools: [Tool]
    /// Selected post profile (`PostProfile.id`).
    public var postProfileID: String?
    /// Selected machine (`MachineDefinition.id` in PostCore). Optional so older files decode; nil
    /// means "the machine whose posts include `postProfileID`, else the post's own limits".
    public var machineID: String?

    public init(document: Document = Document(), operations: [AnyOperation] = [], tools: [Tool] = [],
                postProfileID: String? = nil, machineID: String? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.document = document; self.operations = operations; self.tools = tools
        self.postProfileID = postProfileID
        self.machineID = machineID
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    /// Decodes through `LoftLineFile` so version migrations run and newer files are rejected.
    public static func decode(from data: Data) throws -> LoftLineProject {
        var p = try LoftLineFile.decode(LoftLineProject.self, from: data)
        p.document = p.document.repairingLayers()
        return p
    }

    /// Tool library = project snapshot merged over `library` (library entries win on ID clash).
    public func mergedTools(with library: ToolLibrary) -> ToolLibrary {
        var lib = library
        for t in tools where lib.tool(id: t.id) == nil { lib.upsert(t) }
        return lib
    }
}
