import Foundation

/// Parsing of SVG attribute micro-syntaxes: transform lists, lengths, inline styles.
enum SVGAttributes {
    /// Parse a `transform` list. The returned transform maps element user space to parent
    /// user space (the rightmost item applies first, per SVG).
    static func transform(_ s: String) -> Transform2D {
        var sc = SVGNumberScanner(s)
        var result = Transform2D.identity
        while let name = sc.identifier() {
            guard sc.consume("(") else { break }
            var args: [Double] = []
            while let n = sc.number() { args.append(n) }
            _ = sc.consume(")")
            let t: Transform2D
            switch name {
            case "matrix" where args.count == 6:
                t = Transform2D(a: args[0], b: args[1], c: args[2], d: args[3], tx: args[4], ty: args[5])
            case "translate" where !args.isEmpty:
                t = .translation(Vec2(args[0], args.count > 1 ? args[1] : 0))
            case "scale" where !args.isEmpty:
                t = .scale(args[0], args.count > 1 ? args[1] : args[0])
            case "rotate" where !args.isEmpty:
                let p = args.count >= 3 ? Vec2(args[1], args[2]) : .zero
                t = .rotation(args[0] * .pi / 180, about: p)
            case "skewX" where !args.isEmpty:
                t = Transform2D(a: 1, b: 0, c: tan(args[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where !args.isEmpty:
                t = Transform2D(a: 1, b: tan(args[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                t = .identity
            }
            // Items listed left→right; the last applies to points first.
            result = t.concatenating(result)
        }
        return result
    }

    /// The physical units of a length, as how many make an inch.
    private static let unitsPerInch: [String: Double] = ["in": 1, "mm": 25.4, "cm": 2.54, "pt": 72, "pc": 6]

    /// The number and the unit (lowercased, "" for a bare number) of a length attribute.
    private static func lengthParts(_ s: String?) -> (value: Double, unit: String)? {
        guard let raw = s?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        var sc = SVGNumberScanner(raw)
        guard let v = sc.number() else { return nil }
        let unit = String(raw.utf8.dropFirst(sc.index).map { Character(UnicodeScalar($0)) })
            .trimmingCharacters(in: .whitespaces).lowercased()
        return (v, unit)
    }

    /// True when `s` is a length in a physical unit (in, mm, cm, pt, pc): it fixes a size, whatever the
    /// pixels per inch. "50vmin" is not.
    static func hasPhysicalUnit(_ s: String?) -> Bool {
        guard let unit = lengthParts(s)?.unit else { return false }
        return unitsPerInch[unit] != nil
    }

    /// A length in pixels of an SVG drawn at `pixelsPerInch` (96 by CSS). There is no default: every length of a file
    /// goes through its scale. Percentages resolve against `percentOf`.
    static func pixels(_ s: String?, percentOf ref: Double = 0, pixelsPerInch: Double) -> Double? {
        guard let (v, unit) = lengthParts(s) else { return nil }
        if let perInch = unitsPerInch[unit] { return v * pixelsPerInch / perInch }
        switch unit {
        case "%": return v / 100 * ref
        case "em": return v * 16
        default: return v   // "", "px", and units that are not understood
        }
    }

    /// Declarations from a `style="a:b; c:d"` attribute.
    static func style(_ s: String?) -> [String: String] {
        guard let s else { return [:] }
        var out: [String: String] = [:]
        for decl in s.split(separator: ";") {
            let kv = decl.split(separator: ":", maxSplits: 1)
            guard kv.count == 2 else { continue }
            out[kv[0].trimmingCharacters(in: .whitespaces).lowercased()] = kv[1].trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}
