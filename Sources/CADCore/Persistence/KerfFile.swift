import Foundation

/// Versioned JSON container used by native `.kerf` files.
///
/// Every `.kerf` file is a JSON object with an integer `formatVersion`. Reading runs the
/// registered JSON-level migrations from the file's version up to `currentVersion`, then
/// decodes. Files from a newer Kerf are rejected rather than silently mis-read.
/// `KerfProject` (CAMCore) is the full file; `DocumentFile` reads/writes just the design.
public enum KerfFile {
    public static let fileExtension = "kerf"
    /// Keep in step with `KerfProject.currentFormatVersion`.
    public static let currentVersion = 1

    /// A migration rewrites the top-level JSON object from version N to N + 1.
    public typealias Migration = @Sendable (inout [String: Any]) throws -> Void

    /// Migrations keyed by the version they upgrade FROM.
    /// Add an entry here whenever `currentVersion` is bumped.
    public static let migrations: [Int: Migration] = [:]

    /// The file's `formatVersion` (files without one are treated as version 1).
    public static func formatVersion(of data: Data) throws -> Int {
        try object(from: data)["formatVersion"].flatMap { ($0 as? NSNumber)?.intValue } ?? 1
    }

    /// Decode `type` from `.kerf` JSON, migrating older files first.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data,
                                            migrations: [Int: Migration] = KerfFile.migrations,
                                            currentVersion: Int = KerfFile.currentVersion) throws -> T {
        let upgraded = try migrate(data, migrations: migrations, to: currentVersion)
        do {
            return try JSONDecoder().decode(T.self, from: upgraded)
        } catch let e as DecodingError {
            throw KerfIOError.malformed("Kerf file: \(describe(e))")
        }
    }

    /// Encode as pretty-printed, key-sorted JSON (stable diffs).
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(value)
    }

    /// Apply migrations from the file's version up to `target`; returns the data unchanged
    /// when it is already current.
    public static func migrate(_ data: Data, migrations: [Int: Migration] = KerfFile.migrations,
                               to target: Int = KerfFile.currentVersion) throws -> Data {
        var obj = try object(from: data)
        var v = (obj["formatVersion"] as? NSNumber)?.intValue ?? 1
        if v > target {
            throw KerfIOError.unsupportedFormat("Kerf file version \(v) is newer than this app supports (\(target)).")
        }
        guard v < target else { return data }
        while v < target {
            guard let m = migrations[v] else {
                throw KerfIOError.unsupportedFormat("No migration from Kerf file version \(v).")
            }
            try m(&obj)
            v += 1
            obj["formatVersion"] = v
        }
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    /// Atomic write, creating the parent directory if needed.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func object(from data: Data) throws -> [String: Any] {
        let any: Any
        do { any = try JSONSerialization.jsonObject(with: data) } catch {
            throw KerfIOError.malformed("Kerf file is not valid JSON.")
        }
        guard let obj = any as? [String: Any] else { throw KerfIOError.malformed("Kerf file is not a JSON object.") }
        return obj
    }

    static func describe(_ e: DecodingError) -> String {
        func path(_ c: DecodingError.Context) -> String {
            c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch e {
        case .keyNotFound(let k, let c): return "missing \"\(k.stringValue)\" at \(path(c))"
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .dataCorrupted(let c):
            return "\(c.debugDescription) at \(path(c))"
        @unknown default: return "\(e)"
        }
    }
}

/// Reads and writes the design part of a `.kerf` file. A file written here has no operations
/// and opens as a `KerfProject`; any `.kerf` project can be read here (operations ignored).
public enum DocumentFile {
    struct Envelope: Codable {
        var formatVersion: Int?
        var document: Document
    }

    struct FullEnvelope: Encodable {
        var formatVersion: Int
        var document: Document
        var operations: [String] = []
        var tools: [Tool] = []
    }

    public static func encode(_ document: Document, tools: [Tool] = []) throws -> Data {
        try KerfFile.encode(FullEnvelope(formatVersion: KerfFile.currentVersion, document: document, tools: tools))
    }

    public static func decode(from data: Data) throws -> Document {
        try KerfFile.decode(Envelope.self, from: data).document.repairingLayers()
    }

    public static func save(_ document: Document, to url: URL) throws {
        try KerfFile.write(encode(document), to: url)
    }

    public static func load(from url: URL) throws -> Document {
        try decode(from: Data(contentsOf: url))
    }
}
