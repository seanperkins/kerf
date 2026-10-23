import Foundation

/// LoftLine's built-in single-stroke ("single line") engraving font: each character is a few open
/// centre-line strokes, so text engraves in one pass on the line. Original simple letterforms
/// drawn for LoftLine on a cap-height-1 grid. Lowercase letters use the capital forms.
public enum StrokeFont {
    /// Name shown in font pickers and stored in `TextSpec.fontName`.
    public static let name = "LoftLine Single Line"

    /// The name before the rename. Documents and templates saved by Kerf still store it in `TextSpec.fontName`, and editing their
    /// text looks the font up by name, so it stays recognised.
    public static let legacyName = "Kerf Single Line"

    public static func isStrokeFont(_ fontName: String) -> Bool { fontName == name || fontName == legacyName }

    struct Glyph { var strokes: [[Vec2]]; var width: Double }

    /// Gap added after each character's drawn width (cap-height units).
    static let gap = 0.22
    static let spaceWidth = 0.55
    static let lineHeight = 1.6

    /// Stroke paths for `text`; same layout rules as `TextOutliner` (`size` = cap height,
    /// first baseline at `origin`, lines stack downward, alignment relative to `origin.x`).
    public static func outlines(for text: String, size: Double, origin: Vec2, alignment: TextAlignment = .left,
                                lineSpacing: Double = 1, letterSpacing: Double = 0) -> [Path] {
        guard size > 0 else { return [] }
        var out: [Path] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let gl = glyphs(for: line, size: size, letterSpacing: letterSpacing)
            guard let last = gl.last else { continue }
            let width = last.x + last.advance - letterSpacing - gap * size
            let factor: Double = alignment == .left ? 0 : alignment == .center ? 0.5 : 1
            let o = Vec2(origin.x - max(0, width) * factor, origin.y - Double(i) * lineHeight * size * lineSpacing)
            for g in gl { out += g.paths.map { $0.transformed(.translation(o)) } }
        }
        return out
    }

    /// Per-character strokes of one line (baseline y = 0), for text on a curve.
    public static func glyphs(for text: String, size: Double, letterSpacing: Double = 0) -> [TextGlyph] {
        var x = 0.0
        var out: [TextGlyph] = []
        for ch in text.replacingOccurrences(of: "\n", with: " ") {
            let g = glyph(ch)
            let paths = g.strokes.map { stroke -> Path in
                let pts = stroke.map { Vec2($0.x * size + x, $0.y * size) }
                let closed = pts.count > 3 && pts.first!.isApproximatelyEqual(to: pts.last!, tolerance: 1e-9)
                return Path(points: closed ? Array(pts.dropLast()) : pts, closed: closed)
            }
            let advance = (g.width + (g.strokes.isEmpty ? 0 : gap)) * size + letterSpacing
            out.append(TextGlyph(paths: paths, x: x, advance: advance))
            x += advance
        }
        return out
    }

    // MARK: - Letterforms

    static func glyph(_ c: Character) -> Glyph {
        let u = Character(c.uppercased())
        return table[u] ?? (c == " " ? Glyph(strokes: [], width: spaceWidth) : table["?"]!)
    }

    /// Points along an elliptical arc from `a0` to `a1` degrees (either direction).
    static func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double) -> [Vec2] {
        let n = max(4, Int((abs(a1 - a0) / 10).rounded(.up)))
        return (0...n).map { i in
            let a = (a0 + (a1 - a0) * Double(i) / Double(n)) * .pi / 180
            return Vec2(cx + rx * cos(a), cy + ry * sin(a))
        }
    }

    static func p(_ pts: (Double, Double)...) -> [Vec2] { pts.map { Vec2($0.0, $0.1) } }
    static func dot(_ x: Double, _ y: Double) -> [Vec2] { arc(x, y, 0.035, 0.035, 0, 360) }

    static let table: [Character: Glyph] = {
        var t: [Character: Glyph] = [:]
        t["A"] = Glyph(strokes: [p((0, 0), (0.35, 1), (0.7, 0)), p((0.13, 0.38), (0.57, 0.38))], width: 0.7)
        t["B"] = Glyph(strokes: [p((0, 0.5), (0, 1), (0.38, 1)) + arc(0.38, 0.75, 0.25, 0.25, 90, -90) + p((0, 0.5)),
                                 p((0, 0.5), (0, 0), (0.4, 0)) + arc(0.4, 0.25, 0.27, 0.25, -90, 90) + p((0, 0.5))], width: 0.67)
        t["C"] = Glyph(strokes: [arc(0.45, 0.5, 0.45, 0.5, 45, 315)], width: 0.78)
        t["D"] = Glyph(strokes: [p((0, 0), (0, 1), (0.3, 1)) + arc(0.3, 0.5, 0.4, 0.5, 90, -90) + p((0, 0))], width: 0.7)
        t["E"] = Glyph(strokes: [p((0.6, 1), (0, 1), (0, 0), (0.6, 0)), p((0, 0.5), (0.45, 0.5))], width: 0.6)
        t["F"] = Glyph(strokes: [p((0.6, 1), (0, 1), (0, 0)), p((0, 0.5), (0.45, 0.5))], width: 0.6)
        t["G"] = Glyph(strokes: [arc(0.45, 0.5, 0.45, 0.5, 45, 360) + p((0.5, 0.5))], width: 0.9)
        t["H"] = Glyph(strokes: [p((0, 0), (0, 1)), p((0.7, 0), (0.7, 1)), p((0, 0.5), (0.7, 0.5))], width: 0.7)
        t["I"] = Glyph(strokes: [p((0, 0), (0, 1))], width: 0)
        t["J"] = Glyph(strokes: [p((0.5, 1)) + arc(0.25, 0.25, 0.25, 0.25, 0, -180)], width: 0.5)
        t["K"] = Glyph(strokes: [p((0, 0), (0, 1)), p((0.65, 1), (0, 0.35)), p((0.2, 0.55), (0.65, 0))], width: 0.65)
        t["L"] = Glyph(strokes: [p((0, 1), (0, 0), (0.55, 0))], width: 0.55)
        t["M"] = Glyph(strokes: [p((0, 0), (0, 1), (0.4, 0.3), (0.8, 1), (0.8, 0))], width: 0.8)
        t["N"] = Glyph(strokes: [p((0, 0), (0, 1), (0.7, 0), (0.7, 1))], width: 0.7)
        t["O"] = Glyph(strokes: [arc(0.45, 0.5, 0.45, 0.5, 90, 450)], width: 0.9)
        t["P"] = Glyph(strokes: [p((0, 0), (0, 1), (0.38, 1)) + arc(0.38, 0.75, 0.25, 0.25, 90, -90) + p((0, 0.5))], width: 0.63)
        t["Q"] = Glyph(strokes: [arc(0.45, 0.5, 0.45, 0.5, 90, 450), p((0.52, 0.25), (0.9, -0.05))], width: 0.9)
        t["R"] = Glyph(strokes: [p((0, 0), (0, 1), (0.38, 1)) + arc(0.38, 0.75, 0.25, 0.25, 90, -90) + p((0, 0.5)),
                                 p((0.33, 0.5), (0.65, 0))], width: 0.65)
        t["S"] = Glyph(strokes: [arc(0.33, 0.75, 0.3, 0.25, 20, 270) + arc(0.33, 0.25, 0.32, 0.25, 90, -160)], width: 0.66)
        t["T"] = Glyph(strokes: [p((0, 1), (0.7, 1)), p((0.35, 1), (0.35, 0))], width: 0.7)
        t["U"] = Glyph(strokes: [p((0, 1)) + arc(0.35, 0.3, 0.35, 0.3, 180, 360) + p((0.7, 1))], width: 0.7)
        t["V"] = Glyph(strokes: [p((0, 1), (0.35, 0), (0.7, 1))], width: 0.7)
        t["W"] = Glyph(strokes: [p((0, 1), (0.25, 0), (0.5, 0.7), (0.75, 0), (1, 1))], width: 1)
        t["X"] = Glyph(strokes: [p((0, 0), (0.7, 1)), p((0, 1), (0.7, 0))], width: 0.7)
        t["Y"] = Glyph(strokes: [p((0, 1), (0.35, 0.5), (0.7, 1)), p((0.35, 0.5), (0.35, 0))], width: 0.7)
        t["Z"] = Glyph(strokes: [p((0, 1), (0.7, 1), (0, 0), (0.7, 0))], width: 0.7)
        t["0"] = Glyph(strokes: [arc(0.3, 0.5, 0.3, 0.5, 90, 450)], width: 0.6)
        t["1"] = Glyph(strokes: [p((0.05, 0.8), (0.25, 1), (0.25, 0))], width: 0.3)
        t["2"] = Glyph(strokes: [arc(0.3, 0.7, 0.3, 0.3, 160, -40) + p((0, 0), (0.6, 0))], width: 0.6)
        t["3"] = Glyph(strokes: [arc(0.3, 0.75, 0.27, 0.25, 150, -90) + arc(0.3, 0.25, 0.3, 0.25, 90, -150)], width: 0.6)
        t["4"] = Glyph(strokes: [p((0.45, 0), (0.45, 1), (0, 0.3), (0.65, 0.3))], width: 0.65)
        t["5"] = Glyph(strokes: [p((0.6, 1), (0.1, 1), (0.1, 0.57)) + arc(0.3, 0.32, 0.3, 0.32, 130, -150)], width: 0.6)
        t["6"] = Glyph(strokes: [p((0.5, 1), (0.04, 0.36)), arc(0.32, 0.3, 0.3, 0.3, 0, 360)], width: 0.62)
        t["7"] = Glyph(strokes: [p((0, 1), (0.6, 1), (0.2, 0))], width: 0.6)
        t["8"] = Glyph(strokes: [arc(0.3, 0.76, 0.24, 0.24, -90, 270), arc(0.3, 0.26, 0.3, 0.26, 90, 450)], width: 0.6)
        t["9"] = Glyph(strokes: [arc(0.3, 0.7, 0.3, 0.3, 0, 360), p((0.58, 0.62), (0.28, 0))], width: 0.6)
        t["."] = Glyph(strokes: [dot(0.04, 0.04)], width: 0.08)
        t[","] = Glyph(strokes: [p((0.1, 0.06), (0, -0.15))], width: 0.1)
        t[":"] = Glyph(strokes: [dot(0.04, 0.04), dot(0.04, 0.6)], width: 0.08)
        t[";"] = Glyph(strokes: [p((0.1, 0.06), (0, -0.15)), dot(0.08, 0.6)], width: 0.12)
        t["-"] = Glyph(strokes: [p((0, 0.45), (0.4, 0.45))], width: 0.4)
        t["_"] = Glyph(strokes: [p((0, -0.1), (0.6, -0.1))], width: 0.6)
        t["+"] = Glyph(strokes: [p((0, 0.45), (0.5, 0.45)), p((0.25, 0.2), (0.25, 0.7))], width: 0.5)
        t["="] = Glyph(strokes: [p((0, 0.32), (0.5, 0.32)), p((0, 0.58), (0.5, 0.58))], width: 0.5)
        t["/"] = Glyph(strokes: [p((0, -0.05), (0.5, 1.05))], width: 0.5)
        t["!"] = Glyph(strokes: [p((0.04, 1), (0.04, 0.28)), dot(0.04, 0.04)], width: 0.08)
        t["?"] = Glyph(strokes: [arc(0.28, 0.75, 0.28, 0.25, 160, -60) + p((0.28, 0.3)), dot(0.28, 0.04)], width: 0.56)
        t["'"] = Glyph(strokes: [p((0.04, 1), (0.04, 0.75))], width: 0.08)
        t["\""] = Glyph(strokes: [p((0, 1), (0, 0.75)), p((0.2, 1), (0.2, 0.75))], width: 0.2)
        t["("] = Glyph(strokes: [arc(0.45, 0.45, 0.4, 0.62, 125, 235)], width: 0.25)
        t[")"] = Glyph(strokes: [arc(-0.2, 0.45, 0.4, 0.62, 55, -55)], width: 0.25)
        t["#"] = Glyph(strokes: [p((0.2, 0), (0.3, 1)), p((0.45, 0), (0.55, 1)), p((0.05, 0.33), (0.7, 0.33)), p((0.1, 0.66), (0.75, 0.66))], width: 0.75)
        t["&"] = Glyph(strokes: [p((0.7, 0)) + p((0.15, 0.62)) + arc(0.3, 0.8, 0.18, 0.2, 200, -20) + p((0.1, 0.35))
                                 + arc(0.3, 0.22, 0.22, 0.22, 160, 330) + p((0.7, 0.45))], width: 0.7)
        return t
    }()
}
