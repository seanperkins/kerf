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

    /// The origin after a transform: a similarity scales the stored sizes by `k`; anything else
    /// (shear, non-uniform scale) leaves no circle or rectangle to speak of. Text keeps its spec,
    /// which carries its own transform.
    func transformed(by t: Transform2D) -> ShapeOrigin {
        switch self {
        case .drawn, .imported, .text, .derived: return self
        case .rectangle, .circle, .ellipse, .polygon, .star: break
        }
        guard let k = t.similarityScale else { return .derived(operation: "transform") }
        if abs(k - 1) < 1e-12 { return self }
        switch self {
        case .rectangle(let w, let h, let r): return .rectangle(width: w * k, height: h * k, cornerRadius: r * k)
        case .circle(let r): return .circle(radius: r * k)
        case .ellipse(let rx, let ry): return .ellipse(rx: rx * k, ry: ry * k)
        case .polygon(let n, let r): return .polygon(sides: n, radius: r * k)
        case .star(let n, let ro, let ri): return .star(points: n, outerRadius: ro * k, innerRadius: ri * k)
        default: return self
        }
    }
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
        s.origin = origin.transformed(by: t)
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
    /// Set when the layer holds an extra nesting sheet (layout). Optional so older files decode.
    public var sheet: SheetSlot?
    /// Set when the layer's closed vectors are clamp / fixture zones the tool must stay out
    /// of (layout). They are never machined. Optional so older files decode.
    public var keepOut: LayerKeepOut?
    /// Side of a two-sided job the layer belongs to (nil = top / single-sided).
    public var side: JobSide?
    /// Sheet of a multi-sheet job the layer belongs to (nil = the primary sheet).
    public var sheetID: UUID?

    public init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false,
                colorHex: String = "#000000", sheet: SheetSlot? = nil, keepOut: LayerKeepOut? = nil) {
        self.id = id; self.name = name; self.isVisible = isVisible; self.isLocked = isLocked
        self.colorHex = colorHex; self.sheet = sheet; self.keepOut = keepOut
    }
}
