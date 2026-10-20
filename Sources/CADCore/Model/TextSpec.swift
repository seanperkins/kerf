import Foundation

/// Live text: what a text shape's outlines were built from, so the string, font, size,
/// justification and spacing can be edited again until the text is converted to curves.
///
/// Lengths are in layout space; `transform` maps the layout (first baseline's alignment point at
/// the origin) into the document and follows every move/scale/rotate/mirror of the shape.
public struct TextSpec: Codable, Hashable, Sendable {
    public var string: String
    public var fontName: String
    /// Capital height (layout units).
    public var size: Double
    public var alignment: TextAlignment
    /// Multiplier of the font's natural line height.
    public var lineSpacing: Double
    /// Extra space added after every character (layout units, may be negative).
    public var letterSpacing: Double
    public var transform: Transform2D
    /// Per-letter nudges (kerning): letters are numbered in order, newlines not counted.
    /// Optional so specs written before it existed still decode.
    public var letterAdjustments: [LetterAdjustment]?

    /// Moves and/or rotates one letter of the text (layout units / degrees about its centre).
    public struct LetterAdjustment: Codable, Hashable, Sendable {
        public var index: Int
        public var offset: Vec2
        public var rotation: Double
        public init(index: Int, offset: Vec2 = .zero, rotation: Double = 0) {
            self.index = index; self.offset = offset; self.rotation = rotation
        }
    }

    public init(string: String, fontName: String, size: Double, alignment: TextAlignment = .left,
                lineSpacing: Double = 1, letterSpacing: Double = 0, transform: Transform2D = .identity) {
        self.string = string; self.fontName = fontName; self.size = size; self.alignment = alignment
        self.lineSpacing = lineSpacing; self.letterSpacing = letterSpacing; self.transform = transform
    }

    /// Text placed with its first baseline's alignment point at `anchor`.
    public init(string: String, fontName: String, size: Double, alignment: TextAlignment = .left,
                lineSpacing: Double = 1, letterSpacing: Double = 0, anchor: Vec2) {
        self.init(string: string, fontName: fontName, size: size, alignment: alignment, lineSpacing: lineSpacing,
                  letterSpacing: letterSpacing, transform: .translation(anchor))
    }

    /// Document scale of the layout (1 unless the shape was scaled).
    public var scale: Double { transform.uniformScale }
    /// Capital height as it appears in the document.
    public var displayedSize: Double { size * scale }
}
