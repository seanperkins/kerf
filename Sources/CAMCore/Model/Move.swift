import CADCore
import Foundation

/// One motion command in MACHINE coordinates (see `MachineCoordinates`): XY relative to the
/// job's XY origin, Z per the job's Z-zero mode. Feeds are in document units per minute.
public enum Move: Codable, Hashable, Sendable {
    case rapid(to: Vec3)
    case linear(to: Vec3, feed: Double)
    /// Clockwise arc (G2) in the XY plane around absolute machine-XY `center`;
    /// a Z change makes it a helix.
    case arcCW(to: Vec3, center: Vec2, feed: Double)
    /// Counter-clockwise arc (G3).
    case arcCCW(to: Vec3, center: Vec2, feed: Double)
    case dwell(seconds: Double)

    /// End position, or nil for moves without motion (dwell).
    public var target: Vec3? {
        switch self {
        case .rapid(let p), .linear(let p, _), .arcCW(let p, _, _), .arcCCW(let p, _, _): return p
        case .dwell: return nil
        }
    }

    public var feed: Double? {
        switch self {
        case .linear(_, let f), .arcCW(_, _, let f), .arcCCW(_, _, let f): return f
        case .rapid, .dwell: return nil
        }
    }

    public var isRapid: Bool { if case .rapid = self { return true } else { return false } }
    public var isArc: Bool {
        switch self {
        case .arcCW, .arcCCW: return true
        default: return false
        }
    }
}
