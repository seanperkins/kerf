import CADCore
import Foundation

/// A generated toolpath for ONE tool. Moves are in machine coordinates.
/// Conventions every generator follows:
///  * the first move is `.rapid` to (startXY, coords.safeZ) — the post adds the initial Z
///    retract before it;
///  * every rapid that changes XY happens at or above `coords.safeZ` (the post also
///    enforces this as a safety net);
///  * the last move leaves the tool at `coords.safeZ`.
public struct Toolpath: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The operation that produced this toolpath (nil for ad-hoc paths).
    public var operationID: UUID?
    public var kind: OperationKind
    /// Copy of the tool, converted to the document's units.
    public var tool: Tool
    public var spindleRPM: Double
    public var moves: [Move]
    /// Free-form diagnostics (e.g. "warning": "flat depth limited").
    public var metadata: [String: String]
    /// The operator stop that follows this toolpath in the program. Set when toolpaths are collected
    /// for export, from the operation's `pauseAfter`; generators leave it nil.
    public var pauseAfter: PauseStep?

    public init(id: UUID = UUID(), name: String, operationID: UUID? = nil, kind: OperationKind,
                tool: Tool, spindleRPM: Double? = nil, moves: [Move] = [], metadata: [String: String] = [:]) {
        self.id = id; self.name = name; self.operationID = operationID; self.kind = kind
        self.tool = tool; self.spindleRPM = spindleRPM ?? tool.spindleRPM; self.moves = moves
        self.metadata = metadata
    }

    /// Lowest Z reached by any move (most negative = deepest).
    public var minZ: Double? { moves.compactMap { $0.target?.z }.min() }

    /// XY bounds of all move targets (arcs approximated by their endpoints and centres' extents).
    public var xyBounds: Rect2 { Rect2(points: moves.compactMap { $0.target?.xy }) }
}
