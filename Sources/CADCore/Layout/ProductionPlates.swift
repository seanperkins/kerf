import Foundation

/// A small spreadsheet read from CSV text: a header row of field names and one record per
/// following row (production plates, name badges, numbered tags).
public struct CSVTable: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers; self.rows = rows
    }

    /// Record `i` as field name → value (missing trailing cells are empty).
    public func record(_ i: Int) -> [String: String] {
        guard rows.indices.contains(i) else { return [:] }
        var out: [String: String] = [:]
        for (k, h) in headers.enumerated() where !h.isEmpty && out[h] == nil {
            out[h] = k < rows[i].count ? rows[i][k] : ""
        }
        return out
    }

    /// Parses CSV text. The first non-blank line is the header. Fields may be quoted with `"`
    /// (a doubled `""` is a literal quote; quoted fields may hold the delimiter and newlines).
    /// The delimiter is the first of comma, semicolon or tab found outside quotes in the header
    /// line (spreadsheets in some locales export semicolons). Blank lines are skipped, cells are
    /// trimmed of surrounding spaces unless quoted, and a UTF-8 byte-order mark is ignored.
    public static func parse(_ text: String) -> CSVTable {
        var s = Substring(text)
        if s.first == "\u{FEFF}" { s = s.dropFirst() }
        let delimiter = detectDelimiter(s)
        var records: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false, wasQuoted = false
        var i = s.startIndex
        func endCell() {
            row.append(wasQuoted ? cell : cell.trimmingCharacters(in: .whitespaces))
            cell = ""; wasQuoted = false
        }
        func endRow() {
            endCell()
            if !(row.count == 1 && row[0].isEmpty) { records.append(row) }
            row = []
        }
        while i < s.endIndex {
            let ch = s[i]
            if quoted {
                if ch == "\"" {
                    let next = s.index(after: i)
                    if next < s.endIndex, s[next] == "\"" { cell.append("\""); i = next } else { quoted = false }
                } else {
                    cell.append(ch)
                }
            } else if ch == "\"" && cell.trimmingCharacters(in: .whitespaces).isEmpty {
                quoted = true; wasQuoted = true; cell = ""
            } else if ch == delimiter {
                endCell()
            } else if ch == "\n" || ch == "\r" || ch == "\r\n" {
                endRow()
            } else if !(wasQuoted && !quoted) {
                cell.append(ch)
            }
            i = s.index(after: i)
        }
        if !cell.isEmpty || !row.isEmpty || wasQuoted { endRow() }
        guard let header = records.first else { return CSVTable(headers: [], rows: []) }
        return CSVTable(headers: header, rows: Array(records.dropFirst()))
    }

    static func detectDelimiter(_ s: Substring) -> Character {
        var quoted = false
        for ch in s {
            if ch == "\"" { quoted.toggle(); continue }
            if quoted { continue }
            if ch == "\n" || ch == "\r" || ch == "\r\n" { break }
            if ch == "," || ch == ";" || ch == "\t" { return ch }
        }
        return ","
    }
}

/// Production plates: one design repeated once per spreadsheet record, with `{Field}`
/// placeholders in its text replaced by that record's values.
public enum ProductionPlates {
    /// Placeholder names in `text`, in order of first appearance (`{Name}` → "Name").
    public static func fields(in text: String) -> [String] {
        var out: [String] = []
        for f in placeholders(in: text).map(\.name) where !out.contains(f) { out.append(f) }
        return out
    }

    /// Replaces every `{Field}` whose name matches a record key (case-insensitively, ignoring
    /// surrounding spaces) with its value. Unknown placeholders are left as typed and returned
    /// in `missing`. A value's line breaks are kept (multi-line text).
    public static func fill(_ text: String, record: [String: String]) -> (text: String, missing: [String]) {
        var lookup: [String: String] = [:]
        for (k, v) in record { lookup[normalized(k)] = lookup[normalized(k)] ?? v }
        var out = "", missing: [String] = []
        var last = text.startIndex
        for p in placeholders(in: text) {
            out += text[last..<p.range.lowerBound]
            if let v = lookup[normalized(p.name)] {
                out += v
            } else {
                out += text[p.range]
                if !missing.contains(p.name) { missing.append(p.name) }
            }
            last = p.range.upperBound
        }
        out += text[last...]
        return (out, missing)
    }

    /// Offset of plate `index` (0 = the template itself). Plates fill `columns` across in +X,
    /// then start a new row below (`rowsDown`) or above. `pitch` is centre-to-centre spacing.
    public static func offset(index: Int, columns: Int, pitch: Vec2, rowsDown: Bool = true) -> Vec2 {
        let cols = max(1, columns)
        let c = index % cols, r = index / cols
        return Vec2(Double(c) * pitch.x, Double(r) * pitch.y * (rowsDown ? -1 : 1))
    }

    /// Centre-to-centre spacing for a plate of `size` with `gap` clear between neighbours.
    public static func pitch(size: Vec2, gap: Vec2) -> Vec2 { Vec2(size.x + gap.x, size.y + gap.y) }

    /// Most columns that fit across `material` starting from a template at `template`
    /// (at least 1).
    public static func columnsThatFit(template: Rect2, gapX: Double, material: Rect2) -> Int {
        let step = template.width + gapX
        guard step > 1e-9, !template.isEmpty else { return 1 }
        let room = material.max.x - template.max.x
        return max(1, 1 + Int(((room + 1e-9) / step).rounded(.down)))
    }

    // MARK: Internals

    struct Placeholder { var name: String; var range: Range<String.Index> }

    static func normalized(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

    /// `{name}` runs with a non-empty name that holds no braces or line breaks.
    static func placeholders(in text: String) -> [Placeholder] {
        var out: [Placeholder] = []
        var i = text.startIndex
        while let open = text[i...].firstIndex(of: "{") {
            let after = text.index(after: open)
            guard let close = text[after...].firstIndex(where: { $0 == "}" || $0 == "{" || $0.isNewline }) else { break }
            if text[close] == "}" {
                let name = text[after..<close].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { out.append(Placeholder(name: name, range: open..<text.index(after: close))) }
                i = text.index(after: close)
            } else {
                i = close
            }
        }
        return out
    }
}
