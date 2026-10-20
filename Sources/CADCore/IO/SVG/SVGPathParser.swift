import Foundation

/// Parses SVG path data (`d` attribute) into `Path`s in raw SVG user coordinates (Y down).
/// Supports every command (M L H V C S Q T A Z, absolute and relative). Quadratics become
/// cubics; circular arcs stay `.arc` (sweep > 180° is split), elliptical/rotated arcs become
/// cubics. Parsing stops at the first error, keeping what was parsed (per the SVG spec).
public enum SVGPathParser {
    public static func parse(_ d: String) -> [Path] {
        var sc = SVGNumberScanner(d)
        var paths: [Path] = []
        var current: Path?
        var cur = Vec2.zero, subStart = Vec2.zero
        var lastCubicCtrl: Vec2?, lastQuadCtrl: Vec2?
        var cmd: UInt8 = 0

        func finish() {
            if let p = current, !p.segments.isEmpty { paths.append(p) }
            current = nil
        }
        func ensureStarted() {
            if current == nil { current = Path(start: cur) }
        }
        func add(_ s: PathSegment) {
            ensureStarted()
            current!.segments.append(s)
            cur = s.end
        }
        func finishAll() -> [Path] { finish(); return paths }

        while let c = sc.peek() {
            if SVGNumberScanner.isLetter(c) {
                cmd = c
                sc.advance()
            } else if cmd == 0 {
                break
            } else if cmd == UInt8(ascii: "z") || cmd == UInt8(ascii: "Z") {
                break // numbers after Z are an error
            }
            let rel = cmd >= 0x61
            let base = rel ? cur : .zero
            func pt(_ sc: inout SVGNumberScanner) -> Vec2? {
                guard let x = sc.number(), let y = sc.number() else { return nil }
                return Vec2(x, y) + base
            }
            var resetCubic = true, resetQuad = true
            switch cmd | 0x20 { // lowercase
            case UInt8(ascii: "m"):
                guard let p = pt(&sc) else { return finishAll() }
                finish()
                cur = p; subStart = p
                current = Path(start: p)
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L") // implicit lineto
            case UInt8(ascii: "l"):
                guard let p = pt(&sc) else { return finishAll() }
                add(.line(to: p))
            case UInt8(ascii: "h"):
                guard let x = sc.number() else { return finishAll() }
                add(.line(to: Vec2(rel ? cur.x + x : x, cur.y)))
            case UInt8(ascii: "v"):
                guard let y = sc.number() else { return finishAll() }
                add(.line(to: Vec2(cur.x, rel ? cur.y + y : y)))
            case UInt8(ascii: "c"):
                guard let c1 = pt(&sc), let c2 = pt(&sc), let e = pt(&sc) else { return finishAll() }
                add(.cubic(to: e, control1: c1, control2: c2))
                lastCubicCtrl = c2; resetCubic = false
            case UInt8(ascii: "s"):
                guard let c2 = pt(&sc), let e = pt(&sc) else { return finishAll() }
                let c1 = lastCubicCtrl.map { cur * 2 - $0 } ?? cur
                add(.cubic(to: e, control1: c1, control2: c2))
                lastCubicCtrl = c2; resetCubic = false
            case UInt8(ascii: "q"):
                guard let q = pt(&sc), let e = pt(&sc) else { return finishAll() }
                add(quad(from: cur, q, e))
                lastQuadCtrl = q; resetQuad = false
            case UInt8(ascii: "t"):
                guard let e = pt(&sc) else { return finishAll() }
                let q = lastQuadCtrl.map { cur * 2 - $0 } ?? cur
                add(quad(from: cur, q, e))
                lastQuadCtrl = q; resetQuad = false
            case UInt8(ascii: "a"):
                guard let rx = sc.number(), let ry = sc.number(), let rot = sc.number(),
                      let large = sc.flag(), let sweep = sc.flag(), let e = pt(&sc) else { return finishAll() }
                if e.isApproximatelyEqual(to: cur, tolerance: 1e-12) { break }
                ensureStarted()
                for s in arcSegments(from: cur, to: e, rx: rx, ry: ry, xAxisRotation: rot, largeArc: large, sweep: sweep) {
                    add(s)
                }
            case UInt8(ascii: "z"):
                if var p = current {
                    p.isClosed = true
                    current = p
                }
                finish()
                cur = subStart
            default:
                return finishAll()
            }
            if resetCubic { lastCubicCtrl = nil }
            if resetQuad { lastQuadCtrl = nil }
        }
        finish()
        return paths
    }

    static func quad(from p0: Vec2, _ q: Vec2, _ p: Vec2) -> PathSegment {
        .cubic(to: p, control1: p0 + (q - p0) * (2.0 / 3.0), control2: p + (q - p) * (2.0 / 3.0))
    }

    /// SVG endpoint arc → segments (implementation notes, "F.6.5 conversion").
    /// Arc segments use the raw coordinate system's angle direction: sweep-flag 1 = increasing
    /// angle = `clockwise: false`.
    static func arcSegments(from p1: Vec2, to p2: Vec2, rx rxIn: Double, ry ryIn: Double,
                            xAxisRotation deg: Double, largeArc: Bool, sweep: Bool) -> [PathSegment] {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-12 || ry < 1e-12 { return [.line(to: p2)] }
        let phi = deg * .pi / 180
        let cp = cos(phi), sp = sin(phi)
        let h = (p1 - p2) * 0.5
        let x1p = cp * h.x + sp * h.y
        let y1p = -sp * h.x + cp * h.y
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den > 0 ? (max(0, num) / den).squareRoot() : 0
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let mid = (p1 + p2) * 0.5
        let center = Vec2(cp * cxp - sp * cyp + mid.x, sp * cxp + cp * cyp + mid.y)
        let u = Vec2((x1p - cxp) / rx, (y1p - cyp) / ry)
        let v = Vec2((-x1p - cxp) / rx, (-y1p - cyp) / ry)
        let theta1 = u.angle
        var dtheta = v.angle - u.angle
        if sweep, dtheta < 0 { dtheta += 2 * .pi }
        if !sweep, dtheta > 0 { dtheta -= 2 * .pi }
        guard dtheta.isFinite, center.x.isFinite, center.y.isFinite, rx.isFinite, ry.isFinite else { return [.line(to: p2)] }

        let n = max(1, Int(ceil(abs(dtheta) / (.pi / 2) - 1e-9)))
        let step = dtheta / Double(n)
        if abs(rx - ry) <= 1e-9 * max(rx, ry) {
            // Circular: keep true arcs, split to ≤ 180° pieces so the sweep is unambiguous.
            let pieces = abs(dtheta) > .pi + 1e-9 ? 2 : 1
            var out: [PathSegment] = []
            for i in 1...pieces {
                let a = theta1 + phi + dtheta * Double(i) / Double(pieces)
                let e = i == pieces ? p2 : center + Vec2(cos(a), sin(a)) * rx
                out.append(.arc(to: e, center: center, clockwise: !sweep))
            }
            return out
        }
        // Elliptical: unit-circle cubics mapped through scale(rx, ry) · rotate(phi) · translate.
        let k = 4.0 / 3.0 * tan(step / 4)
        func map(_ q: Vec2) -> Vec2 {
            let x = q.x * rx, y = q.y * ry
            return Vec2(cp * x - sp * y + center.x, sp * x + cp * y + center.y)
        }
        var out: [PathSegment] = []
        var a = theta1
        for i in 0..<n {
            let b = a + step
            let s0 = Vec2(cos(a), sin(a)), s1 = Vec2(cos(b), sin(b))
            let c1 = s0 + Vec2(-s0.y, s0.x) * k
            let c2 = s1 - Vec2(-s1.y, s1.x) * k
            out.append(.cubic(to: i == n - 1 ? p2 : map(s1), control1: map(c1), control2: map(c2)))
            a = b
        }
        return out
    }
}
