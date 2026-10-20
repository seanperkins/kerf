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

    /// XY bounds of everything the moves reach, including the bulge of arcs (the quadrant points
    /// an arc passes through). Used to decide whether two toolpaths can be reordered safely, so
    /// it must never be smaller than the truth.
    public var xyBounds: Rect2 {
        var pts: [Vec2] = []
        var pos: Vec2?
        for m in moves {
            switch m {
            case .arcCW(let p, let c, _), .arcCCW(let p, let c, _):
                if let s = pos {
                    let cw: Bool = { if case .arcCW = m { return true } else { return false } }()
                    let r = s.distance(to: c)
                    let sweep = Flattening.arcSweep(from: s, to: p.xy, center: c, clockwise: cw)
                    let a0 = (s - c).angle
                    for k in 0..<4 {
                        let a = Double(k) * .pi / 2
                        var d = (a - a0).truncatingRemainder(dividingBy: 2 * .pi)   // CCW offset from the start
                        if d < 0 { d += 2 * .pi }
                        let inside = d < 1e-12 || (sweep >= 0 ? d <= sweep : 2 * .pi - d <= -sweep)
                        if inside { pts.append(c + Vec2(cos(a), sin(a)) * r) }
                    }
                }
                pts.append(p.xy)
                pos = p.xy
            case .rapid(let p), .linear(let p, _):
                pts.append(p.xy)
                pos = p.xy
            case .dwell:
                break
            }
        }
        return Rect2(points: pts)
    }
}
