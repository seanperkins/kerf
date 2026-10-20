import Foundation

/// One DXF entity: its type ("LINE", …) and its group-code/value pairs in file order.
struct DXFEntity {
    var type: String
    var pairs: [(code: Int, value: String)]
    /// POLYLINE: its VERTEX entities.
    var vertices: [DXFEntity] = []

    func string(_ code: Int) -> String? { pairs.first { $0.code == code }?.value }
    func double(_ code: Int) -> Double? { string(code).flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
    func int(_ code: Int) -> Int? { double(code).map { Int($0) } }
    func doubles(_ code: Int) -> [Double] {
        pairs.filter { $0.code == code }.compactMap { Double($0.value.trimmingCharacters(in: .whitespaces)) }
    }
    var layer: String { string(8) ?? "0" }
    /// OCS extrusion Z < 0 means the entity's X axis is mirrored relative to WCS.
    var isMirroredOCS: Bool { (double(230) ?? 1) < 0 }
}

struct DXFBlock {
    var name: String
    var base: Vec2
    var entities: [DXFEntity]
}

/// Tokenised ASCII DXF: header variables, layer table colours, blocks and model-space entities.
struct DXFFile {
    var header: [String: [(code: Int, value: String)]] = [:]
    var layerColors: [String: Int] = [:]
    var blocks: [String: DXFBlock] = [:]
    var entities: [DXFEntity] = []

    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw KerfIOError.malformed("DXF: unreadable text encoding")
        }
        if text.hasPrefix("AutoCAD Binary DXF") { throw KerfIOError.unsupportedFormat("Binary DXF") }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            .map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
        var pairs: [(Int, String)] = []
        pairs.reserveCapacity(lines.count / 2)
        var i = 0
        while i + 1 < lines.count {
            guard let code = Int(lines[i].trimmingCharacters(in: .whitespaces)) else {
                throw KerfIOError.malformed("DXF: bad group code at line \(i + 1)")
            }
            pairs.append((code, String(lines[i + 1]).trimmingCharacters(in: .whitespaces)))
            i += 2
        }
        guard pairs.contains(where: { $0.0 == 0 && $0.1 == "SECTION" }) else {
            throw KerfIOError.malformed("DXF: no SECTION found")
        }
        parse(pairs)
    }

    private mutating func parse(_ pairs: [(Int, String)]) {
        var i = 0
        while i < pairs.count {
            guard pairs[i] == (0, "SECTION"), i + 1 < pairs.count, pairs[i + 1].0 == 2 else { i += 1; continue }
            let name = pairs[i + 1].1
            var j = i + 2
            while j < pairs.count, !(pairs[j].0 == 0 && pairs[j].1 == "ENDSEC") { j += 1 }
            let body = Array(pairs[(i + 2)..<min(j, pairs.count)])
            switch name {
            case "HEADER": parseHeader(body)
            case "TABLES": parseTables(body)
            case "BLOCKS": parseBlocks(body)
            case "ENTITIES": entities = Self.entities(in: body)
            default: break
            }
            i = j + 1
        }
    }

    private mutating func parseHeader(_ body: [(Int, String)]) {
        var current: String?
        for (code, value) in body {
            if code == 9 { current = value; header[value] = [] } else if let c = current { header[c]?.append((code, value)) }
        }
    }

    private mutating func parseTables(_ body: [(Int, String)]) {
        for e in Self.entities(in: body) where e.type == "LAYER" {
            if let name = e.string(2), let color = e.int(62) { layerColors[name] = abs(color) }
        }
    }

    private mutating func parseBlocks(_ body: [(Int, String)]) {
        var current: DXFBlock?
        var pending: [(Int, String)] = []
        func flush() {
            guard var b = current else { return }
            b.entities = Self.entities(in: pending)
            blocks[b.name] = b
        }
        var i = 0
        while i < body.count {
            let (code, value) = body[i]
            if code == 0, value == "BLOCK" {
                var k = i + 1
                var head: [(Int, String)] = []
                while k < body.count, body[k].0 != 0 { head.append(body[k]); k += 1 }
                let e = DXFEntity(type: "BLOCK", pairs: head.map { (code: $0.0, value: $0.1) })
                current = DXFBlock(name: e.string(2) ?? "", base: Vec2(e.double(10) ?? 0, e.double(20) ?? 0), entities: [])
                pending = []
                i = k
                continue
            }
            if code == 0, value == "ENDBLK" { flush(); current = nil; pending = [] } else if current != nil { pending.append(body[i]) }
            i += 1
        }
    }

    /// Split a group list into entities; VERTEX…SEQEND are folded into their POLYLINE.
    static func entities(in body: [(Int, String)]) -> [DXFEntity] {
        var out: [DXFEntity] = []
        var cur: DXFEntity?
        var polyline: DXFEntity?
        func emit(_ e: DXFEntity) {
            switch e.type {
            case "POLYLINE": polyline = e
            case "VERTEX": polyline?.vertices.append(e)
            case "SEQEND": if let p = polyline { out.append(p) }; polyline = nil
            default:
                if let p = polyline { out.append(p); polyline = nil }
                out.append(e)
            }
        }
        for (code, value) in body {
            if code == 0 {
                if let e = cur { emit(e) }
                cur = DXFEntity(type: value.uppercased(), pairs: [])
            } else {
                cur?.pairs.append((code, value))
            }
        }
        if let e = cur { emit(e) }
        if let p = polyline { out.append(p) }
        return out
    }

    func headerInt(_ name: String, code: Int = 70) -> Int? {
        header[name]?.first { $0.code == code }.flatMap { Int($0.value) }
    }
}
