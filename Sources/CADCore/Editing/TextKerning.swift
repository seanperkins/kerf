import CoreText
import Foundation

/// Letter-by-letter layout of live text with per-letter moves and rotations.
public enum TextKerning {
    /// Line pitch for `fontName` at cap height `size` (same rules as the normal layout).
    static func lineHeight(fontName: String, size: Double, lineSpacing: Double) throws -> Double {
        if StrokeFont.isStrokeFont(fontName) { return StrokeFont.lineHeight * size * lineSpacing }
        let font = try TextOutliner.font(named: fontName, capHeight: size)
        return (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) * lineSpacing
    }

    /// Number of letters (glyphs) the adjustments can address.
    public static func letterCount(_ spec: TextSpec) throws -> Int {
        try spec.string.components(separatedBy: "\n").reduce(0) {
            $0 + (try TextOutliner().glyphs(for: $1, fontName: spec.fontName, size: spec.size, letterSpacing: spec.letterSpacing).count)
        }
    }

    static func outlines(for spec: TextSpec, adjustments: [TextSpec.LetterAdjustment], outliner: TextOutliner) throws -> [Path] {
        let byIndex = Dictionary(adjustments.map { ($0.index, $0) }, uniquingKeysWith: { _, b in b })
        let pitch = try lineHeight(fontName: spec.fontName, size: spec.size, lineSpacing: spec.lineSpacing)
        var out: [Path] = []
        var index = 0
        for (i, line) in spec.string.components(separatedBy: "\n").enumerated() {
            let glyphs = try outliner.glyphs(for: line, fontName: spec.fontName, size: spec.size, letterSpacing: spec.letterSpacing)
            guard let last = glyphs.last else { continue }
            var width = last.x + last.advance - spec.letterSpacing
            if StrokeFont.isStrokeFont(spec.fontName) { width = max(0, width - StrokeFont.gap * spec.size) }
            let factor: Double = spec.alignment == .left ? 0 : spec.alignment == .center ? 0.5 : 1
            let lineShift = Vec2(-width * factor, -Double(i) * pitch)
            for g in glyphs {
                var t = Transform2D.identity
                if let a = byIndex[index] {
                    let c = Vec2(g.x + g.advance / 2, spec.size / 2)
                    t = Transform2D.rotation(a.rotation * .pi / 180, about: c).concatenating(.translation(a.offset))
                }
                t = t.concatenating(.translation(lineShift)).concatenating(spec.transform)
                out += g.paths.map { $0.transformed(t) }
                index += 1
            }
        }
        return out
    }
}
