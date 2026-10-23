import Foundation

/// Reading and writing tool lists for sharing between machines (toolpaths-2d addition).
///
/// Two formats:
/// * `.loftlinetools` — pretty JSON `{ "formatVersion": 1, "tools": [...] }`. Lossless (groups,
///   per-material data, ids). A plain `tools.json` copied from another Mac is also accepted.
/// * `.csv` — one tool per row with a header, for spreadsheets. Per-material data and form-tool
///   outlines are not included; a missing `id` column gives the tools new ids.
public enum ToolLibraryExchange {
    public static let fileExtension = "loftlinetools"
    public static let formatVersion = 1

    public enum ExchangeError: Error, LocalizedError, Equatable {
        case unreadable(String)
        case newerFormat(Int)
        case noTools

        public var errorDescription: String? {
            switch self {
            case .unreadable(let why): return "The file is not a tool list: \(why)"
            case .newerFormat(let v): return "The tool file uses format \(v), which is newer than this version of LoftLine."
            case .noTools: return "The file contains no tools."
            }
        }
    }

    struct File: Codable {
        var formatVersion: Int
        var tools: [Tool]
    }

    // MARK: JSON

    public static func encodeJSON(_ tools: [Tool]) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(File(formatVersion: formatVersion, tools: tools))
    }

    /// Reads a `.loftlinetools` file or a bare `tools.json` library.
    public static func decodeJSON(_ data: Data) throws -> [Tool] {
        let dec = JSONDecoder()
        if let probe = try? dec.decode(VersionProbe.self, from: data), let v = probe.formatVersion,
           v > formatVersion {
            throw ExchangeError.newerFormat(v)
        }
        let tools: [Tool]
        if let f = try? dec.decode(File.self, from: data) {
            tools = f.tools
        } else {
            do { tools = try dec.decode(ToolLibrary.self, from: data).tools } catch {
                throw ExchangeError.unreadable(error.localizedDescription)
            }
        }
        guard !tools.isEmpty else { throw ExchangeError.noTools }
        return tools
    }

    private struct VersionProbe: Decodable { var formatVersion: Int? }

    // MARK: CSV

    static let csvColumns = ["id", "number", "name", "type", "units", "diameter", "flutes", "angle",
                             "tip_diameter", "flute_length", "corner_radius", "ball_tip_radius", "taper_half_angle", "stepdown",
                             "stepover", "rpm", "feed", "plunge", "group", "notes"]

    public static func encodeCSV(_ tools: [Tool]) -> String {
        var rows = [csvColumns.joined(separator: ",")]
        for t in tools {
            let fields: [String] = [
                t.id.uuidString, String(t.number), t.name, t.kind.rawValue, t.units.rawValue,
                num(t.diameter), String(t.flutes), t.angle.map(num) ?? "", num(t.tipDiameter),
                t.fluteLength.map(num) ?? "", shapeField(t, 0), shapeField(t, 1), shapeField(t, 2),
                num(t.stepdown), num(t.stepover),
                num(t.spindleRPM), num(t.feedRate), num(t.plungeRate), t.group ?? "", t.notes,
            ]
            rows.append(fields.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Reads CSV written by `encodeCSV` (or by hand / a spreadsheet: columns may be in any order,
    /// only `name`, `type` and `diameter` are required; header names are case-insensitive).
    public static func decodeCSV(_ text: String) throws -> [Tool] {
        let records = parseCSV(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = records.first else { throw ExchangeError.noTools }
        let cols = Dictionary(header.enumerated().map {
            ($0.element.trimmingCharacters(in: .whitespaces).lowercased(), $0.offset)
        }, uniquingKeysWith: { a, _ in a })
        for required in ["name", "type", "diameter"] where cols[required] == nil {
            throw ExchangeError.unreadable("missing the \"\(required)\" column")
        }
        var tools: [Tool] = []
        for (line, rec) in records.dropFirst().enumerated() {
            func s(_ k: String) -> String? {
                guard let i = cols[k], i < rec.count else { return nil }
                let v = rec[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            func d(_ k: String) throws -> Double? {
                guard let v = s(k) else { return nil }
                guard let x = Double(v), x.isFinite else {
                    throw ExchangeError.unreadable("row \(line + 2): \"\(v)\" in \(k) is not a number")
                }
                return x
            }
            guard let name = s("name") else { continue }
            guard let kindText = s("type"), let kind = ToolKind(csvName: kindText) else {
                throw ExchangeError.unreadable("row \(line + 2): unknown tool type \"\(s("type") ?? "")\"")
            }
            guard let dia = try d("diameter"), dia > 0 else {
                throw ExchangeError.unreadable("row \(line + 2): the diameter must be above zero")
            }
            let units = s("units").flatMap { LengthUnit(csvName: $0) } ?? .inch
            var t = Tool(name: name, kind: kind, units: units, number: s("number").flatMap { Int($0) } ?? 1,
                         diameter: dia, flutes: s("flutes").flatMap { Int($0) } ?? 2, angle: try d("angle"),
                         tipDiameter: try d("tip_diameter") ?? 0, fluteLength: try d("flute_length"),
                         stepdown: try d("stepdown") ?? dia / 2, stepover: try d("stepover") ?? dia * 0.4,
                         spindleRPM: try d("rpm") ?? 18000, feedRate: try d("feed") ?? 60,
                         plungeRate: try d("plunge") ?? 20, notes: s("notes") ?? "", group: s("group"))
            if let c = try d("corner_radius"), c > 0 {
                t.shape = .bullNose(cornerRadius: c)
            } else if let tip = try d("ball_tip_radius"), let half = try d("taper_half_angle") {
                t.shape = .taperedBallNose(tipRadius: tip, halfAngle: half)
            }
            if let idText = s("id"), let id = UUID(uuidString: idText) { t.id = id }
            tools.append(t)
        }
        guard !tools.isEmpty else { throw ExchangeError.noTools }
        return tools
    }

    /// Picks the format from the file extension (`csv` or JSON otherwise).
    public static func read(_ url: URL) throws -> [Tool] {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "csv" {
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw ExchangeError.unreadable("not text")
            }
            return try decodeCSV(text)
        }
        return try decodeJSON(data)
    }

    public static func write(_ tools: [Tool], to url: URL) throws {
        let data = url.pathExtension.lowercased() == "csv" ? Data(encodeCSV(tools).utf8) : try encodeJSON(tools)
        try data.write(to: url, options: .atomic)
    }

    /// Bull-nose / tapered-ball columns (form tool outlines are only kept in .loftlinetools).
    private static func shapeField(_ t: Tool, _ column: Int) -> String {
        switch (t.shape, column) {
        case (.bullNose(let c)?, 0): return num(c)
        case (.taperedBallNose(let tip, _)?, 1): return num(tip)
        case (.taperedBallNose(_, let a)?, 2): return num(a)
        default: return ""
        }
    }

    private static func num(_ x: Double) -> String {
        x == x.rounded() && abs(x) < 1e15 ? String(Int(x)) : String(x)
    }

    private static func csvEscape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// RFC 4180-style parser: quoted fields may hold commas, quotes ("") and newlines.
    static func parseCSV(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.unicodeScalars)[...]
        if chars.first == "\u{FEFF}" { chars = chars.dropFirst() }
        var i = chars.startIndex
        while i < chars.endIndex {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    let n = chars.index(after: i)
                    if n < chars.endIndex, chars[n] == "\"" { field.unicodeScalars.append("\""); i = n } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                record.append(field); field = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r", chars.index(after: i) < chars.endIndex, chars[chars.index(after: i)] == "\n" {
                    i = chars.index(after: i)
                }
                record.append(field); field = ""
                records.append(record); record = []
            } else {
                field.unicodeScalars.append(c)
            }
            i = chars.index(after: i)
        }
        if !field.isEmpty || !record.isEmpty { record.append(field); records.append(record) }
        return records
    }
}

/// What to do with an imported tool whose id is already in the library.
public enum ToolImportPolicy: String, CaseIterable, Sendable {
    /// Overwrite the library's tool with the imported one.
    case replace
    /// Keep the library's tool; add the imported one as a new tool.
    case keepBoth
    /// Keep the library's tool and ignore the imported one.
    case skip
}

public struct ToolImportReport: Equatable, Sendable {
    public var added = 0
    public var replaced = 0
    public var skipped = 0
    /// Tools whose number clashed with another tool and were given a free number.
    public var renumbered: [String] = []

    public init() {}

    public var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if replaced > 0 { parts.append("\(replaced) replaced") }
        if skipped > 0 { parts.append("\(skipped) unchanged or skipped") }
        if !renumbered.isEmpty { parts.append("renumbered: " + renumbered.joined(separator: ", ")) }
        return parts.isEmpty ? "Nothing to import." : parts.joined(separator: "; ") + "."
    }
}

extension ToolLibrary {
    /// Ids of `incoming` tools that already exist in the library with different contents.
    public func conflicts(with incoming: [Tool]) -> [Tool] {
        incoming.filter { t in tool(id: t.id).map { $0 != t } ?? false }
    }

    /// Merges imported tools. Identical tools (same id and contents) are left alone. Tool numbers
    /// stay unique: an imported tool whose number another tool already uses gets the smallest
    /// free number (reported).
    @discardableResult
    public mutating func merge(_ incoming: [Tool], policy: ToolImportPolicy) -> ToolImportReport {
        var report = ToolImportReport()
        var seenIDs = Set<UUID>()
        for var t in incoming {
            if seenIDs.contains(t.id) { t.id = UUID() } // duplicate ids inside the file
            seenIDs.insert(t.id)
            if let existing = tool(id: t.id) {
                if existing == t { report.skipped += 1; continue }
                switch policy {
                case .skip: report.skipped += 1; continue
                case .replace:
                    renumberIfClashing(&t, ignoring: t.id, report: &report)
                    upsert(t); report.replaced += 1
                    continue
                case .keepBoth:
                    t.id = UUID()
                    seenIDs.insert(t.id)
                    if tools.contains(where: { $0.name == t.name }) { t.name += " (imported)" }
                }
            }
            renumberIfClashing(&t, ignoring: nil, report: &report)
            tools.append(t)
            report.added += 1
        }
        return report
    }

    private func renumberIfClashing(_ t: inout Tool, ignoring id: UUID?, report: inout ToolImportReport) {
        let used = Set(tools.filter { $0.id != id }.map(\.number))
        guard used.contains(t.number) else { return }
        var n = 1
        while used.contains(n) { n += 1 }
        report.renumbered.append("\(t.name) T\(t.number)→T\(n)")
        t.number = n
    }
}

extension ToolKind {
    /// Accepts the raw value or the display name ("End Mill", "ball nose", "vbit").
    init?(csvName: String) {
        let key = csvName.lowercased().filter { $0.isLetter }
        guard let k = ToolKind.allCases.first(where: {
            $0.rawValue.lowercased() == key || $0.displayName.lowercased().filter(\.isLetter) == key
        }) else { return nil }
        self = k
    }
}

extension LengthUnit {
    init?(csvName: String) {
        let key = csvName.lowercased().trimmingCharacters(in: .whitespaces)
        switch key {
        case "in", "inch", "inches", "\"": self = .inch
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres": self = .millimeter
        default: return nil
        }
    }
}
