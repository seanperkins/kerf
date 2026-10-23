import CADCore
import Foundation
import PostCore

/// Built-in post profiles plus user profiles stored as JSON in
/// ~/Library/Application Support/LoftLine/posts/*.json (a user file with a built-in's id overrides it).
struct PostProfileStore {
    var directory: URL
    /// False = the built-ins only, whatever is in `directory` (the command line's `--builtin-only`).
    var readsUserFiles = true

    init(directory: URL = ToolLibraryStore.supportDirectory.appendingPathComponent("posts", isDirectory: true)) {
        self.directory = directory
    }

    static let defaultProfileID = BuiltInPosts.avidMach4Inch.id

    func userProfiles() -> [PostProfile] {
        guard readsUserFiles else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? PostProfile.fromJSON(Data(contentsOf: $0)) }
    }

    func allProfiles() -> [PostProfile] {
        let user = userProfiles()
        let userIDs = Set(user.map(\.id))
        return BuiltInPosts.all.filter { !userIDs.contains($0.id) } + user
    }

    func profile(id: String?) -> PostProfile {
        let all = allProfiles()
        return all.first { $0.id == id } ?? all.first { $0.id == Self.defaultProfileID } ?? BuiltInPosts.avidMach4Inch
    }

    /// Default profile for a document's units (Avid inch/mm).
    static func defaultID(for units: LengthUnit) -> String {
        units == .inch ? BuiltInPosts.avidMach4Inch.id : BuiltInPosts.avidMach4MM.id
    }

    func save(_ profile: PostProfile) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(profile.id).appendingPathExtension("json")
        try profile.toJSON().write(to: url, options: .atomic)
        return url
    }
}
