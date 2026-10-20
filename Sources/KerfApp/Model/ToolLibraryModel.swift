import CADCore
import Combine
import Foundation

/// The shared, persisted tool database (CRUD + autosave). One instance per app.
final class ToolLibraryModel: ObservableObject {
    @Published private(set) var library: ToolLibrary
    /// Bumped on every change so documents can mark toolpaths stale.
    @Published private(set) var revision = 0
    @Published var lastError: String?
    let store: ToolLibraryStore

    static let shared = ToolLibraryModel(store: ToolLibraryStore())

    init(store: ToolLibraryStore) {
        self.store = store
        do { library = try store.load() } catch {
            library = .seeded
            lastError = "Could not read \(store.fileURL.path): \(error.localizedDescription). Using default tools."
        }
    }

    var tools: [Tool] { library.tools }

    /// Smallest tool number not used yet.
    var nextToolNumber: Int {
        let used = Set(library.tools.map(\.number))
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    /// A reasonable starting tool of `kind` in `units`.
    static func template(kind: ToolKind, units: LengthUnit, number: Int) -> Tool {
        let f = LengthUnit.inch.factor(to: units)
        let base: Tool
        switch kind {
        case .endMill:
            base = Tool(name: "New End Mill", kind: .endMill, diameter: 0.25, stepdown: 0.125, stepover: 0.1,
                        feedRate: 100, plungeRate: 30)
        case .ballNose:
            base = Tool(name: "New Ball Nose", kind: .ballNose, diameter: 0.25, stepdown: 0.1, stepover: 0.025,
                        feedRate: 100, plungeRate: 30)
        case .vBit:
            base = Tool(name: "New V-Bit", kind: .vBit, diameter: 0.5, angle: 60, stepdown: 0.1, stepover: 0.02,
                        feedRate: 80, plungeRate: 30)
        case .engraving:
            base = Tool(name: "New Engraving Bit", kind: .engraving, diameter: 0.125, flutes: 1, angle: 30,
                        tipDiameter: 0.01, stepdown: 0.02, stepover: 0.005, spindleRPM: 20000, feedRate: 40,
                        plungeRate: 15)
        case .drill:
            base = Tool(name: "New Drill", kind: .drill, diameter: 0.25, stepdown: 0.125, stepover: 0,
                        spindleRPM: 12000, feedRate: 30, plungeRate: 20)
        }
        var t = base.converted(to: units)
        t.number = number
        return t
    }

    @discardableResult
    func add(kind: ToolKind, units: LengthUnit = .inch) -> Tool {
        let t = Self.template(kind: kind, units: units, number: nextToolNumber)
        mutate { $0.upsert(t) }
        return t
    }

    func update(_ tool: Tool) { mutate { $0.upsert(tool) } }

    @discardableResult
    func duplicate(id: UUID) -> Tool? {
        guard var t = library.tool(id: id) else { return nil }
        t.id = UUID()
        t.name += " copy"
        t.number = nextToolNumber
        mutate { $0.upsert(t) }
        return t
    }

    func delete(id: UUID) { mutate { $0.remove(id: id) } }

    /// Adds any of the seeded defaults that are missing (by id); never deletes user tools.
    func restoreDefaults() {
        mutate { lib in for t in ToolLibrary.seeded.tools where lib.tool(id: t.id) == nil { lib.upsert(t) } }
    }

    /// Imports tools from a project snapshot into the library (skips IDs already present).
    func importTools(_ tools: [Tool]) {
        let missing = tools.filter { library.tool(id: $0.id) == nil }
        guard !missing.isEmpty else { return }
        mutate { lib in missing.forEach { lib.upsert($0) } }
    }

    /// Tools in a `.kerftools`/`tools.json`/`.csv` file, and which of them would overwrite a
    /// different library tool with the same id.
    func readImport(_ url: URL) throws -> (tools: [Tool], conflicts: [Tool]) {
        let tools = try ToolLibraryExchange.read(url)
        return (tools, library.conflicts(with: tools))
    }

    /// Merges imported tools into the library (see `ToolLibrary.merge`).
    @discardableResult
    func importTools(_ tools: [Tool], policy: ToolImportPolicy) -> ToolImportReport {
        var lib = library
        let report = lib.merge(tools, policy: policy)
        guard lib != library else { return report }
        mutate { $0 = lib }
        return report
    }

    /// Writes the tools with `ids` (all tools when nil) in the format of `url`'s extension.
    func export(ids: Set<UUID>?, to url: URL) throws {
        let tools = ids.map { ids in library.tools.filter { ids.contains($0.id) } } ?? library.tools
        try ToolLibraryExchange.write(tools, to: url)
    }

    private func mutate(_ change: (inout ToolLibrary) -> Void) {
        change(&library)
        revision += 1
        do { try store.save(library); lastError = nil } catch {
            lastError = "Could not save tools: \(error.localizedDescription)"
        }
    }
}
