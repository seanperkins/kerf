import Foundation

/// Loads/saves the tool database as JSON (default: ~/Library/Application Support/Kerf/tools.json).
public struct ToolLibraryStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL = ToolLibraryStore.defaultURL) { self.fileURL = fileURL }

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Kerf", isDirectory: true)
    }

    public static var defaultURL: URL { supportDirectory.appendingPathComponent("tools.json") }

    /// Returns the stored library, or the seeded defaults if none exists yet.
    public func load() throws -> ToolLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .seeded }
        return try JSONDecoder().decode(ToolLibrary.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ library: ToolLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(library).write(to: fileURL, options: .atomic)
    }
}
