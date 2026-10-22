import CADCore
import Foundation

/// Lengths and an estimated run time for a toolpath (feeds + rapids + dwells, no
/// acceleration model). Lengths are in the toolpath's units; feeds are units/minute.
public struct ToolpathStats: Hashable, Sendable {
    public var cutLength = 0.0
    public var rapidLength = 0.0
    /// Minutes spent feeding (Σ length / feed).
    public var cutMinutes = 0.0
    public var dwellSeconds = 0.0

    public init(_ toolpath: Toolpath) {
        var cur: Vec3?
        for m in toolpath.moves {
            switch m {
            case .dwell(let s):
                dwellSeconds += max(0, s)
            case .rapid(let p):
                if let c = cur { rapidLength += c.distance(to: p) }
                cur = p
            case .linear(let p, let f):
                if let c = cur {
                    let l = c.distance(to: p)
                    cutLength += l
                    if f > 0 { cutMinutes += l / f }
                }
                cur = p
            case .arcCW(let p, let center, let f), .arcCCW(let p, let center, let f):
                if let c = cur {
                    let cw: Bool
                    if case .arcCW = m { cw = true } else { cw = false }
                    let l = Self.arcLength(from: c, to: p, center: center, clockwise: cw)
                    cutLength += l
                    if f > 0 { cutMinutes += l / f }
                }
                cur = p
            }
        }
    }

    /// Helical arc length (planar sweep × radius, combined with the Z change).
    public static func arcLength(from a: Vec3, to b: Vec3, center: Vec2, clockwise: Bool) -> Double {
        let r = a.xy.distance(to: center)
        var sweep = abs(Flattening.arcSweep(from: a.xy, to: b.xy, center: center, clockwise: clockwise))
        if sweep < 1e-12, a.xy.distance(to: b.xy) < 1e-9 { sweep = 2 * .pi }
        let planar = sweep * r
        let dz = b.z - a.z
        return (planar * planar + dz * dz).squareRoot()
    }

    /// Estimated seconds at `rapidRate` (units/minute).
    public func estimatedSeconds(rapidRate: Double) -> TimeInterval {
        let rapid = rapidRate > 0 ? rapidLength / rapidRate : 0
        return (cutMinutes + rapid) * 60 + dwellSeconds
    }

    /// True when the machine stops between `previous` and `next`: a different tool, or a pause after `previous`.
    public static func stopsBefore(_ next: Toolpath, after previous: Toolpath) -> Bool {
        previous.tool.id != next.tool.id || previous.tool.number != next.tool.number || previous.pauseAfter != nil
    }
}
