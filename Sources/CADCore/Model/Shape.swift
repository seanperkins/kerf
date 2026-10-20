import Foundation

/// How a shape was created; lets the UI re-open parametric editors. Purely informational
/// for CAM — CAM always works on `Shape.paths`.
public enum ShapeOrigin: Codable, Hashable, Sendable {
    case drawn
    case imported(format: String)
    case rectangle(width: Double, height: Double, cornerRadius: Double)
    case circle(radius: Double)
    case ellipse(rx: Double, ry: Double)
    case polygon(sides: Int, radius: Double)
    case star(points: Int, outerRadius: Double, innerRadius: Double)
    case text(String, fontName: String, size: Double)
    case derived(operation: String)
}

/// A drawable object: one or more paths (e.g. a letter "O" is two closed paths).
public struct Shape: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var layerID: UUID
    public var paths: [Path]
    public var origin: ShapeOrigin
    public var isLocked: Bool
    /// Shapes sharing a group ID are selected and transformed together (nil = ungrouped).
    /// Optional so files written before grouping existed still decode.
    public var groupID: UUID?
    /// Live text the paths were outlined from (nil = plain vectors). Optional so older files decode.
    public var text: TextSpec?
    /// Groups this shape belonged to before `groupID` was formed, outermost first (nested
    /// groups: ungrouping restores them one level at a time). Nil = not nested.
    public var innerGroupIDs: [UUID]?

    public init(id: UUID = UUID(), name: String = "", layerID: UUID, paths: [Path],
                origin: ShapeOrigin = .drawn, isLocked: Bool = false, groupID: UUID? = nil, text: TextSpec? = nil) {
        self.id = id; self.name = name; self.layerID = layerID; self.paths = paths
        self.origin = origin; self.isLocked = isLocked; self.groupID = groupID; self.text = text
    }

    public var isClosed: Bool { !paths.isEmpty && paths.allSatisfy(\.isClosed) }

    public func bounds(tolerance: Double = Path.defaultTolerance) -> Rect2 {
        paths.reduce(Rect2.empty) { $0.union($1.bounds(tolerance: tolerance)) }
    }

    public func transformed(_ t: Transform2D) -> Shape {
        var s = self
        s.paths = paths.map { $0.transformed(t) }
        s.text?.transform = (text?.transform ?? .identity).concatenating(t)
        return s
    }
}

/// A named group of shapes, VCarve-style.
public struct Layer: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    /// sRGB hex, e.g. "#1E90FF".
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false,
                colorHex: String = "#000000") {
        self.id = id; self.name = name; self.isVisible = isVisible; self.isLocked = isLocked
        self.colorHex = colorHex
    }
}
