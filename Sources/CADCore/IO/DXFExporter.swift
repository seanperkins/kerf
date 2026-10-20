import Foundation

/// DXF (R12 ASCII) export. Each path becomes one POLYLINE with arc bulges (cubics are
/// flattened with `curveTolerance`); full circles become CIRCLE entities. Units are recorded
/// in `$INSUNITS` / `$MEASUREMENT`.
public struct DXFExporter: VectorExporter {
    public static let fileExtension = "dxf"
    /// Chordal tolerance for flattening Béziers, in document units.
    public var curveTolerance: Double?

    public init(curveTolerance: Double? = nil) { self.curveTolerance = curveTolerance }

    public func export(shapes: [Shape], layers: [Layer], units: LengthUnit) throws -> Data {
        let tol = curveTolerance ?? (units == .inch ? 0.0005 : 0.01)
        var w = DXFWriter()
        w.section("HEADER") {
            $0.pair(9, "$ACADVER"); $0.pair(1, "AC1009")
            $0.pair(9, "$INSUNITS"); $0.pair(70, units == .inch ? "1" : "4")
            $0.pair(9, "$MEASUREMENT"); $0.pair(70, units == .inch ? "0" : "1")
        }
        var names: [UUID: String] = [:]
        var used = Set<String>()
        for l in layers {
            var n = Self.layerName(l.name)
            var k = 2
            while used.contains(n.uppercased()) { n = Self.layerName(l.name) + "_\(k)"; k += 1 }
            used.insert(n.uppercased()); names[l.id] = n
        }
        w.section("TABLES") { w in
            w.pair(0, "TABLE"); w.pair(2, "LAYER"); w.pair(70, "\(layers.count + 1)")
            w.pair(0, "LAYER"); w.pair(2, "0"); w.pair(70, "0"); w.pair(62, "7"); w.pair(6, "CONTINUOUS")
            for (i, l) in layers.enumerated() {
                w.pair(0, "LAYER"); w.pair(2, names[l.id]!); w.pair(70, "0")
                w.pair(62, "\((l.isVisible ? 1 : -1) * Self.aci(l.colorHex, fallback: i))"); w.pair(6, "CONTINUOUS")
            }
            w.pair(0, "ENDTAB")
        }
        w.section("ENTITIES") { w in
            for s in shapes {
                let layer = names[s.layerID] ?? "0"
                for p in s.paths where !p.segments.isEmpty { Self.write(p, layer: layer, tolerance: tol, to: &w) }
            }
        }
        w.pair(0, "EOF")
        return Data(w.text.utf8)
    }

    static func write(_ p: Path, layer: String, tolerance: Double, to w: inout DXFWriter) {
        if let (c, r) = fullCircle(p) {
            w.pair(0, "CIRCLE"); w.pair(8, layer)
            w.xy(c); w.pair(30, "0"); w.pair(40, w.num(r))
            return
        }
        var verts: [(Vec2, Double)] = [(p.start, 0)]
        var cur = p.start
        for seg in p.segments {
            switch seg {
            case .line(let to):
                verts.append((to, 0))
            case .arc(let to, let c, let cw):
                let sweep = Flattening.arcSweep(from: cur, to: to, center: c, clockwise: cw)
                let pieces = abs(sweep) > .pi + 1e-9 ? 2 : 1
                let r = cur.distance(to: c), a0 = (cur - c).angle
                for i in 1...pieces {
                    verts[verts.count - 1].1 = tan(sweep / Double(pieces) / 4)
                    let a = a0 + sweep * Double(i) / Double(pieces)
                    verts.append((i == pieces ? to : c + Vec2(cos(a), sin(a)) * r, 0))
                }
            case .cubic:
                var pts: [Vec2] = []
                Flattening.append(segment: seg, from: cur, tolerance: tolerance, to: &pts)
                verts += pts.map { ($0, 0) }
            }
            cur = seg.end
        }
        if p.isClosed, verts.count > 1, verts.last!.0.isApproximatelyEqual(to: p.start, tolerance: 1e-9) {
            verts.removeLast()
        }
        w.pair(0, "POLYLINE"); w.pair(8, layer); w.pair(66, "1")
        w.xy(.zero); w.pair(30, "0"); w.pair(70, p.isClosed ? "1" : "0")
        for (v, b) in verts {
            w.pair(0, "VERTEX"); w.pair(8, layer); w.xy(v); w.pair(30, "0")
            if b != 0 { w.pair(42, w.num(b)) }
        }
        w.pair(0, "SEQEND"); w.pair(8, layer)
    }

    /// Centre and radius when `p` is a closed path made only of arcs on one circle covering 360°.
    static func fullCircle(_ p: Path) -> (Vec2, Double)? {
        guard p.isClosed, p.end.isApproximatelyEqual(to: p.start, tolerance: 1e-9) else { return nil }
        var center: Vec2?, total = 0.0
        var cur = p.start
        for seg in p.segments {
            guard case .arc(let to, let c, let cw) = seg else { return nil }
            if let k = center, !k.isApproximatelyEqual(to: c, tolerance: 1e-9) { return nil }
            center = c
            total += Flattening.arcSweep(from: cur, to: to, center: c, clockwise: cw)
            cur = to
        }
        guard let c = center, abs(abs(total) - 2 * .pi) < 1e-6 else { return nil }
        return (c, p.start.distance(to: c))
    }

    static func layerName(_ s: String) -> String {
        let bad = Set("<>/\\\":;?*|=`,")
        let n = String(s.map { bad.contains($0) ? "_" : $0 }).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Layer" : n
    }

    /// Nearest of the 7 basic AutoCAD colours to `hex` (black/white → 7).
    static func aci(_ hex: String, fallback: Int) -> Int {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = Int(h, radix: 16) else { return fallback % 6 + 1 }
        let r = Double((v >> 16) & 255), g = Double((v >> 8) & 255), b = Double(v & 255)
        let table: [(Int, Double, Double, Double)] = [(1, 255, 0, 0), (2, 255, 255, 0), (3, 0, 255, 0), (4, 0, 255, 255),
                                                      (5, 0, 0, 255), (6, 255, 0, 255), (7, 0, 0, 0), (7, 255, 255, 255)]
        return table.min { a, c in
            let da = (a.1 - r) * (a.1 - r) + (a.2 - g) * (a.2 - g) + (a.3 - b) * (a.3 - b)
            let dc = (c.1 - r) * (c.1 - r) + (c.2 - g) * (c.2 - g) + (c.3 - b) * (c.3 - b)
            return da < dc
        }!.0
    }
}

/// Group-code/value text builder.
struct DXFWriter {
    var text = ""

    mutating func pair(_ code: Int, _ value: String) {
        text += "\(code < 10 ? "  " : code < 100 ? " " : "")\(code)\n\(value)\n"
    }

    mutating func xy(_ v: Vec2) { pair(10, num(v.x)); pair(20, num(v.y)) }

    mutating func section(_ name: String, _ body: (inout DXFWriter) -> Void) {
        pair(0, "SECTION"); pair(2, name)
        body(&self)
        pair(0, "ENDSEC")
    }

    func num(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}
