import Foundation

/// EPS / legacy Illustrator import: a tiny PostScript path interpreter (no general
/// programming). Supports moveto/lineto/curveto/closepath and their relative forms,
/// Illustrator's m l c v y h + paint operators, single-operator procedure aliases
/// (`/m {moveto} bind def`), gsave/grestore, translate/scale/rotate/concat.
/// Units are PostScript points (1/72 in); geometry is placed relative to %%BoundingBox.
public struct EPSImporter: VectorImporter {
    public static let fileExtensions = ["eps", "ai"]
    public init() {}

    public func importVectors(from data: Data, targetUnits: LengthUnit) throws -> ImportResult {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw KerfIOError.malformed("EPS: unreadable text")
        }
        if text.hasPrefix("%PDF") {
            // Illustrator 9+ .ai files are PDF documents.
            return try PDFImporter().importVectors(from: data, targetUnits: targetUnits)
        }
        guard text.hasPrefix("%!") || text.contains("%!PS") else { throw KerfIOError.malformed("EPS: missing %!PS header") }

        let ptToUnit = LengthUnit.inch.convert(1.0 / 72, to: targetUnits)
        var bboxOrigin = Vec2.zero
        if let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("%%BoundingBox:") }) {
            let n = line.dropFirst("%%BoundingBox:".count).split(separator: " ").compactMap { Double($0) }
            if n.count == 4 { bboxOrigin = Vec2(n[0], n[1]) }
        }
        var interp = Interpreter()
        interp.run(text)
        let toDoc = Transform2D.translation(-bboxOrigin).concatenating(.scale(ptToUnit, ptToUnit))
        let layer = Layer(name: "EPS Import", colorHex: SVGImporter.palette[0])
        let shapes = interp.shapes.map {
            Shape(name: "Path", layerID: layer.id, paths: $0.map { $0.transformed(toDoc) }, origin: .imported(format: "eps"))
        }
        var warnings: [String] = []
        if !interp.unknown.isEmpty {
            warnings.append("Ignored PostScript operators: \(interp.unknown.sorted().prefix(10).joined(separator: ", ")).")
        }
        return ImportResult(layers: shapes.isEmpty ? [] : [layer], shapes: shapes, warnings: warnings)
    }

    struct Interpreter {
        var stack: [Double] = []
        var ctm = Transform2D.identity
        var saved: [Transform2D] = []
        var aliases: [String: String] = [:]
        var current: [Path] = []
        var sub: Path?
        var point = Vec2.zero
        var subStart = Vec2.zero
        var shapes: [[Path]] = []
        var unknown: Set<String> = []

        static let painters: Set<String> = ["fill", "eofill", "stroke", "f", "F", "s", "S", "b", "B", "B*", "b*", "f*", "F*"]
        static let closingPainters: Set<String> = ["s", "b", "f", "b*", "f*"]
        static let ignored: Set<String> = ["setlinewidth", "setgray", "setrgbcolor", "setcmykcolor", "setlinecap",
                                           "setlinejoin", "setmiterlimit", "setdash", "showpage", "bind", "def",
                                           "pop", "dup", "exch", "load", "begin", "end", "save", "restore",
                                           "clip", "eoclip", "W", "u", "U", "w", "j", "J", "M", "d", "g", "G",
                                           "k", "K", "x", "X", "A", "D", "i", "Xa", "XA", "*u", "*U"]

        mutating func run(_ text: String) {
            var tokens: [Substring] = []
            for line in text.split(whereSeparator: \.isNewline) {
                let code = line.firstIndex(of: "%").map { line[..<$0] } ?? line[...]
                tokens += code.split(whereSeparator: { $0 == " " || $0 == "\t" })
            }
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                // `/name {op} bind def` → alias name → op
                if t.hasPrefix("/"), i + 3 < tokens.count, tokens[i + 1] == "{", tokens[i + 3] == "}" {
                    aliases[String(t.dropFirst())] = String(tokens[i + 2])
                    i += 4
                    while i < tokens.count, tokens[i] == "bind" || tokens[i] == "def" { i += 1 }
                    continue
                }
                // `/name {op} bind def` written without spaces inside the braces
                if t.hasPrefix("/"), i + 1 < tokens.count, tokens[i + 1].count > 2,
                   tokens[i + 1].hasPrefix("{"), tokens[i + 1].hasSuffix("}") {
                    aliases[String(t.dropFirst())] = String(tokens[i + 1].dropFirst().dropLast())
                    i += 2
                    while i < tokens.count, tokens[i] == "bind" || tokens[i] == "def" { i += 1 }
                    continue
                }
                if t.hasPrefix("/") || t.hasPrefix("(") || t == "{" || t == "}" { i += 1; continue }
                if t.hasPrefix("[") || t.hasSuffix("]") {
                    let inner = t.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    if let v = Double(inner) { stack.append(v) }
                    i += 1; continue
                }
                if let v = Double(t) { stack.append(v) } else { exec(String(t)) }
                i += 1
            }
            flushShape()
        }

        mutating func pop(_ n: Int) -> [Double]? {
            guard stack.count >= n else { stack.removeAll(); return nil }
            defer { stack.removeLast(n) }
            return Array(stack.suffix(n))
        }

        mutating func exec(_ op: String) {
            let op = aliases[op] ?? op
            switch op {
            case "moveto", "m":
                guard let a = pop(2) else { return }
                startSub(Vec2(a[0], a[1]))
            case "rmoveto":
                guard let a = pop(2) else { return }
                startSub(point + Vec2(a[0], a[1]))
            case "lineto", "l", "L":
                guard let a = pop(2) else { return }
                lineTo(Vec2(a[0], a[1]))
            case "rlineto":
                guard let a = pop(2) else { return }
                lineTo(point + Vec2(a[0], a[1]))
            case "curveto", "c", "C":
                guard let a = pop(6) else { return }
                curve(Vec2(a[0], a[1]), Vec2(a[2], a[3]), Vec2(a[4], a[5]))
            case "rcurveto":
                guard let a = pop(6) else { return }
                curve(point + Vec2(a[0], a[1]), point + Vec2(a[2], a[3]), point + Vec2(a[4], a[5]))
            case "v", "V": // first control point = current point
                guard let a = pop(4) else { return }
                curve(point, Vec2(a[0], a[1]), Vec2(a[2], a[3]))
            case "y", "Y": // second control point = end point
                guard let a = pop(4) else { return }
                curve(Vec2(a[0], a[1]), Vec2(a[2], a[3]), Vec2(a[2], a[3]))
            case "closepath", "h", "H":
                closeSub()
            case "newpath", "n", "N":
                endSub(); current.removeAll()
            case "gsave", "q": saved.append(ctm)
            case "grestore", "Q": ctm = saved.popLast() ?? ctm
            case "translate":
                guard let a = pop(2) else { return }
                ctm = Transform2D.translation(Vec2(a[0], a[1])).concatenating(ctm)
            case "scale":
                guard let a = pop(2) else { return }
                ctm = Transform2D.scale(a[0], a[1]).concatenating(ctm)
            case "rotate":
                guard let a = pop(1) else { return }
                ctm = Transform2D.rotation(a[0] * .pi / 180).concatenating(ctm)
            case "concat", "cm":
                guard let a = pop(6) else { return }
                ctm = Transform2D(a: a[0], b: a[1], c: a[2], d: a[3], tx: a[4], ty: a[5]).concatenating(ctm)
            default:
                if Self.painters.contains(op) {
                    if Self.closingPainters.contains(op) { closeSub() }
                    flushShape()
                } else if !Self.ignored.contains(op) {
                    unknown.insert(op)
                    stack.removeAll()
                }
            }
        }

        mutating func startSub(_ p: Vec2) {
            endSub()
            point = p
            subStart = p
            sub = Path(start: ctm.apply(p))
        }

        mutating func lineTo(_ p: Vec2) {
            if sub == nil { sub = Path(start: ctm.apply(point)) }
            sub!.segments.append(.line(to: ctm.apply(p)))
            point = p
        }

        mutating func curve(_ c1: Vec2, _ c2: Vec2, _ e: Vec2) {
            if sub == nil { sub = Path(start: ctm.apply(point)) }
            sub!.segments.append(.cubic(to: ctm.apply(e), control1: ctm.apply(c1), control2: ctm.apply(c2)))
            point = e
        }

        mutating func closeSub() {
            guard var s = sub else { return }
            s.isClosed = true
            if s.segments.count > 1, case .line(let to) = s.segments.last!, to.isApproximatelyEqual(to: s.start, tolerance: 1e-9) {
                s.segments.removeLast()
            }
            sub = s
            endSub()
            point = subStart
        }

        mutating func endSub() {
            if let s = sub, !s.segments.isEmpty { current.append(s) }
            sub = nil
        }

        mutating func flushShape() {
            endSub()
            if !current.isEmpty { shapes.append(current) }
            current.removeAll()
        }
    }
}
