import CADCore
import Foundation

/// Axially symmetric cutter profile used by the simulator: how far above the tool tip the
/// cutting surface sits at a given radial distance from the tool axis.
public enum ToolShape: Hashable, Sendable {
    case flat(radius: Double)
    case ball(radius: Double)
    /// V / engraving cutter: flat tip of `tipRadius`, flanks rising at `halfAngle` (radians,
    /// measured from the axis) out to `radius`.
    case vee(radius: Double, tipRadius: Double, halfAngle: Double)
    /// Bull nose, tapered ball nose or form tool (toolpaths-2d addition).
    case shaped(radius: Double, shape: CutterShape)

    public init(tool: Tool) {
        let r = max(tool.radius, 1e-9)
        if let s = tool.effectiveShape { self = .shaped(radius: r, shape: s); return }
        switch tool.kind {
        case .endMill:
            self = .flat(radius: r)
        case .ballNose:
            self = .ball(radius: r)
        case .vBit, .engraving, .drill:
            if let a = tool.angle, a > 0, a < 180 {
                self = .vee(radius: r, tipRadius: min(r, tool.tipDiameter / 2), halfAngle: a / 2 * .pi / 180)
            } else {
                self = .flat(radius: r)
            }
        }
    }

    public var radius: Double {
        switch self {
        case .flat(let r), .ball(let r), .vee(let r, _, _), .shaped(let r, _): return r
        }
    }

    /// Height of the cutting surface above the tip at radial distance `r`, or nil if `r` is
    /// outside the tool.
    public func heightAboveTip(atRadius r: Double) -> Double? {
        switch self {
        case .flat(let radius):
            return r <= radius ? 0 : nil
        case .ball(let radius):
            guard r <= radius else { return nil }
            return radius - (radius * radius - r * r).squareRoot()
        case .vee(let radius, let tip, let half):
            guard r <= radius else { return nil }
            return r <= tip ? 0 : (r - tip) / tan(half)
        case .shaped(let radius, let shape):
            return shape.heightAboveTip(atRadius: r, toolRadius: radius)
        }
    }
}
