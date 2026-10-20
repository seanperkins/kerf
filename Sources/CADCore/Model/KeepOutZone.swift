import Foundation

/// An area the tool must stay out of, e.g. a clamp: a closed outline in the material frame plus
/// the height of its top above the material top. Toolpaths are checked against it on export
/// (toolpaths-2d addition).
public struct KeepOutZone: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// Closed polygon (no repeated closing point), document units, material frame.
    public var outline: [Vec2]
    /// Top of the obstacle above the material top (0 = flush with the top).
    public var height: Double

    public init(id: UUID = UUID(), name: String, outline: [Vec2], height: Double) {
        self.id = id; self.name = name; self.outline = outline; self.height = height
    }
}
