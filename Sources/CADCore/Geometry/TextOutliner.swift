import CoreGraphics
import CoreText
import Foundation

/// Horizontal alignment of text relative to the origin X.
public enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

/// Converts text to vector outlines using CoreText (any installed font).
///
/// `size` is the CAP HEIGHT in document units (the height of a capital "H"), which is what a
/// CNC user measures on the finished piece; the font's point size is derived from it.
/// Multi-line text (separated by "\n") stacks downward from the first baseline at `origin`.
/// Outer contours are counter-clockwise, holes clockwise.
public struct TextOutliner: Sendable {
    public init() {}

    public enum TextError: Error, Equatable, Sendable {
        case fontNotFound(String)
    }

    /// Outline paths for `text` with the first baseline's left end at `origin`.
    public func outlines(for text: String, fontName: String, size: Double, origin: Vec2) throws -> [Path] {
        try outlines(for: text, fontName: fontName, size: size, origin: origin, alignment: .left)
    }

    /// Outline paths for `text`; `alignment` positions each line relative to `origin.x`.
    /// `lineSpacing` multiplies the font's natural line height.
    public func outlines(for text: String, fontName: String, size: Double, origin: Vec2,
                         alignment: TextAlignment, lineSpacing: Double = 1) throws -> [Path] {
        guard size > 0 else { return [] }
        let font = try Self.font(named: fontName, capHeight: size)
        let lineHeight = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) * lineSpacing
        var out: [Path] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() where !line.isEmpty {
            let attr = NSAttributedString(string: line, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let ctLine = CTLineCreateWithAttributedString(attr)
            let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            let factor: Double = alignment == .left ? 0 : alignment == .center ? 0.5 : 1
            let lineOrigin = Vec2(origin.x - width * factor, origin.y - Double(i) * lineHeight)
            out += glyphOutlines(ctLine, at: lineOrigin, fallback: font)
        }
        return out
    }

    /// A text `Shape` (provenance recorded for re-editing).
    public func shape(for text: String, fontName: String, size: Double, origin: Vec2,
                      alignment: TextAlignment = .left, layerID: UUID) throws -> Shape {
        let paths = try outlines(for: text, fontName: fontName, size: size, origin: origin, alignment: alignment)
        return Shape(name: text, layerID: layerID, paths: paths, origin: .text(text, fontName: fontName, size: size))
    }

    /// Installed font family names for the UI picker (sorted, hidden system fonts removed).
    public static func availableFontNames() -> [String] {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Font whose capital height equals `capHeight`. Accepts family, full or PostScript names.
    static func font(named name: String, capHeight: Double) throws -> CTFont {
        let probe = CTFontCreateWithName(name as CFString, 100, nil)
        let wanted = name.lowercased()
        let candidates = [CTFontCopyFamilyName(probe), CTFontCopyPostScriptName(probe), CTFontCopyFullName(probe)]
            .map { ($0 as String).lowercased() }
        guard candidates.contains(wanted) else { throw TextError.fontNotFound(name) }
        var cap = CTFontGetCapHeight(probe) / 100
        if cap <= 0 { cap = 0.7 }
        return CTFontCreateWithName(name as CFString, capHeight / cap, nil)
    }

    private func glyphOutlines(_ line: CTLine, at o: Vec2, fallback: CTFont) -> [Path] {
        var out: [Path] = []
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String].map { $0 as! CTFont } ?? fallback
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
            for k in 0..<n {
                var t = CGAffineTransform(translationX: positions[k].x + o.x, y: positions[k].y + o.y)
                guard let cg = CTFontCreatePathForGlyph(runFont, glyphs[k], &t) else { continue }
                out += PathGeometry.normalizedOrientation(Self.paths(from: cg))
            }
        }
        return out
    }

    /// Convert a CGPath into `Path`s (quadratics become cubics).
    static func paths(from cg: CGPath) -> [Path] {
        var out: [Path] = []
        var cur: Path?
        func finish() {
            if var p = cur, !p.segments.isEmpty {
                if p.isClosed, case .line(let to) = p.segments.last!, to == p.start, p.segments.count > 1 {
                    p.segments.removeLast()
                }
                out.append(p)
            }
            cur = nil
        }
        cg.applyWithBlock { el in
            let e = el.pointee
            func pt(_ i: Int) -> Vec2 { Vec2(Double(e.points[i].x), Double(e.points[i].y)) }
            switch e.type {
            case .moveToPoint:
                finish()
                cur = Path(start: pt(0))
            case .addLineToPoint:
                cur?.segments.append(.line(to: pt(0)))
            case .addQuadCurveToPoint:
                if let p = cur {
                    cur?.segments.append(SVGPathParser.quad(from: p.end, pt(0), pt(1)))
                }
            case .addCurveToPoint:
                cur?.segments.append(.cubic(to: pt(2), control1: pt(0), control2: pt(1)))
            case .closeSubpath:
                cur?.isClosed = true
                finish()
            @unknown default:
                break
            }
        }
        finish()
        return out
    }
}
