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

    /// A length in CSS pixels (SVG user units). Percentages resolve against `percentOf`.
    static func pixels(_ s: String?, percentOf ref: Double = 0) -> Double? {
        guard let raw = s?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        var sc = SVGNumberScanner(raw)
        guard let v = sc.number() else { return nil }
        let unit = String(raw.utf8.dropFirst(sc.index).map { Character(UnicodeScalar($0)) })
            .trimmingCharacters(in: .whitespaces).lowercased()
        switch unit {
        case "", "px": return v
        case "in": return v * 96
        case "mm": return v * 96 / 25.4
        case "cm": return v * 96 / 2.54
        case "pt": return v * 96 / 72
        case "pc": return v * 16
        case "%": return v / 100 * ref
        case "em": return v * 16
        default: return v
        }
    }

    /// A length converted to `unit` (physical: 96 px per inch).
    static func physical(_ s: String?, in unit: LengthUnit, percentOf ref: Double = 0) -> Double? {
        pixels(s, percentOf: ref).map { LengthUnit.inch.convert($0 / 96, to: unit) }
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
