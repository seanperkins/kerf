import Foundation

/// Converts text to vector outlines using CoreText (any installed font).
public struct TextOutliner: Sendable {
    public init() {}

    /// Outline paths for `text` with the baseline origin at `origin`; `size` is the cap
    /// height-ish font size in document units.
    public func outlines(for text: String, fontName: String, size: Double, origin: Vec2) throws -> [Path] {
        // TODO(cad-io): CTFontCreatePathForGlyph per glyph → CGPath → Path (quad → cubic).
        throw KerfIOError.notImplemented("TextOutliner")
    }

    /// Installed font family names for the UI picker.
    public static func availableFontNames() -> [String] {
        // TODO(cad-io): CTFontManagerCopyAvailableFontFamilyNames.
        []
    }
}
