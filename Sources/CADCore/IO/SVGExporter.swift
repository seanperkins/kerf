import Foundation

/// SVG export with physical width/height in document units. One `<g>` per layer (Inkscape
/// layer attributes), one `<path>` per shape. Arcs are written as SVG `A` commands, cubics as
/// `C`. The page spans from min(0, bounds.min) to bounds.max so designs in the material frame
/// round-trip through `SVGImporter` unchanged.
public struct SVGExporter: VectorExporter {
    public static let fileExtension = "svg"
    public var decimals: Int
    public var strokeWidth: Double?

    public init(decimals: Int = 5, strokeWidth: Double? = nil) {
        self.decimals = decimals; self.strokeWidth = strokeWidth
    }

    public func export(shapes: [Shape], layers: [Layer], units: LengthUnit) throws -> Data {
        let b = PathGeometry.bounds(of: shapes)
        let minX = b.isEmpty ? 0 : min(0, b.min.x), minY = b.isEmpty ? 0 : min(0, b.min.y)
        let maxX = b.isEmpty ? 1 : max(b.max.x, minX + 1e-6), maxY = b.isEmpty ? 1 : max(b.max.y, minY + 1e-6)
        let w = maxX - minX, h = maxY - minY
        let unit = units == .inch ? "in" : "mm"
        let sw = strokeWidth ?? (units == .inch ? 0.01 : 0.25)
        // SVG y = top - y_doc, i.e. user y runs from -maxY (top) to -minY (bottom).
        var out = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" \
        version="1.1" width="\(f(w))\(unit)" height="\(f(h))\(unit)" viewBox="\(f(minX)) \(f(-maxY)) \(f(w)) \(f(h))">

        """
        var byLayer: [UUID: [Shape]] = [:]
        for s in shapes { byLayer[s.layerID, default: []].append(s) }
        var ordered = layers.filter { byLayer[$0.id] != nil }
        for id in Set(byLayer.keys).subtracting(layers.map(\.id)).sorted(by: { $0.uuidString < $1.uuidString }) {
            ordered.append(Layer(id: id, name: "Layer"))
        }
        for layer in ordered {
            let color = layer.colorHex.isEmpty ? "#000000" : layer.colorHex
            out += "  <g id=\"\(xmlEscape(layerID(layer)))\" inkscape:label=\"\(xmlEscape(layer.name))\" inkscape:groupmode=\"layer\""
            if !layer.isVisible { out += " style=\"display:none\"" }
            out += " fill=\"none\" stroke=\"\(xmlEscape(color))\" stroke-width=\"\(f(sw))\">\n"
            for s in byLayer[layer.id] ?? [] {
                let d = s.paths.map(pathData).joined(separator: " ")
                guard !d.isEmpty else { continue }
                let name = s.name.isEmpty ? "" : " id=\"\(xmlEscape(uniqueID(s)))\""
                out += "    <path\(name) d=\"\(d)\"/>\n"
            }
            out += "  </g>\n"
        }
        out += "</svg>\n"
        return Data(out.utf8)
    }

    func pathData(_ p: Path) -> String {
        guard !p.segments.isEmpty else { return "" }
        var parts = ["M\(pt(p.start))"]
        var cur = p.start
        for seg in p.segments {
            switch seg {
            case .line(let to):
                parts.append("L\(pt(to))")
            case .arc(let to, let c, let cw):
                let r = cur.distance(to: c)
                let sweep = Flattening.arcSweep(from: cur, to: to, center: c, clockwise: cw)
                // Split (near-)full circles: SVG cannot express start == end.
                let pieces = abs(sweep) > .pi * 1.5 ? 2 : 1
                let a0 = (cur - c).angle
                for i in 1...pieces {
                    let e = i == pieces ? to : c + Vec2(cos(a0 + sweep / 2), sin(a0 + sweep / 2)) * r
                    let large = abs(sweep) / Double(pieces) > .pi ? 1 : 0
                    // Y is flipped: a CCW document arc runs toward decreasing angles in SVG
                    // user space, i.e. sweep-flag 0; a CW arc is sweep-flag 1.
                    parts.append("A\(f(r)) \(f(r)) 0 \(large) \(cw ? 1 : 0) \(pt(e))")
                }
            case .cubic(let to, let c1, let c2):
                parts.append("C\(pt(c1)) \(pt(c2)) \(pt(to))")
            }
            cur = seg.end
        }
        if p.isClosed { parts.append("Z") }
        return parts.joined(separator: " ")
    }

    private func pt(_ v: Vec2) -> String { "\(f(v.x)),\(f(-v.y))" }

    func f(_ v: Double) -> String {
        var s = String(format: "%.\(decimals)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    private func layerID(_ l: Layer) -> String { "layer-" + l.id.uuidString.prefix(8).lowercased() }
    private func uniqueID(_ s: Shape) -> String {
        let base = s.name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return (base.isEmpty ? "shape" : base) + "-" + Self.hashSuffix(of: s.id)
    }

    /// The first eight hex digits of `id`, lowercased, with at least one letter a-f: that is how `SVGImporter`
    /// tells this suffix from a date or a revision ("Rev-20240101") and drops it. A UUID that starts with eight
    /// decimal digits (about 2 in 100) has its first digit turned into a letter, so its name survives a round
    /// trip; two such ids collide only if the other seven digits match too (one in 270 million).
    static func hashSuffix(of id: UUID) -> String {
        var digits = Array(id.uuidString.prefix(8).lowercased())
        if !digits.contains(where: { "abcdef".contains($0) }), let d = digits[0].wholeNumberValue {
            digits[0] = Array("abcdef")[d % 6]
        }
        return String(digits)
    }
}

func xmlEscape(_ s: String) -> String {
    var o = ""
    for ch in s {
        switch ch {
        case "&": o += "&amp;"
        case "<": o += "&lt;"
        case ">": o += "&gt;"
        case "\"": o += "&quot;"
        case "'": o += "&apos;"
        default: o.append(ch)
        }
    }
    return o
}
