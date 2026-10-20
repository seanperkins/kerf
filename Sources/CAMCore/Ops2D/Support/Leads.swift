import CADCore
import Foundation

/// Lead-in / lead-out moves on the waste side of a closed loop.
public enum Leads {
    /// Points from the lead-in start up to (excluding) `start`.
    /// - Parameters:
    ///   - tangent: unit direction of travel at `start`.
    ///   - waste: unit normal pointing into the waste side.
    public static func leadIn(to start: Vec2, tangent t: Vec2, waste n: Vec2, settings: LeadSettings,
                              tolerance: Double) -> [Vec2] {
        let d = settings.distance
        guard d > 0 else { return [] }
        switch settings.type {
        case .none: return []
        case .linear:
            return [start + (n - t).normalized * d]
        case .arc:
            let c = start + n * d
            return arcPoints(count: segments(radius: d, tolerance: tolerance)) { th in
                // θ runs π/2 → 0 (exclusive of the end point at θ = 0).
                let a = Double.pi / 2 * (1 - th)
                return c + (n * -cos(a) - t * sin(a)) * d
            }
        }
    }

    /// Points after `end` (excluding it) leaving into the waste.
    public static func leadOut(from end: Vec2, tangent t: Vec2, waste n: Vec2, settings: LeadSettings,
                               tolerance: Double) -> [Vec2] {
        let d = settings.distance
        guard d > 0 else { return [] }
        switch settings.type {
        case .none: return []
        case .linear:
            return [end + (n + t).normalized * d]
        case .arc:
            let c = end + n * d
            let pts = arcPoints(count: segments(radius: d, tolerance: tolerance)) { th in
                let a = Double.pi / 2 * th
                return c + (n * -cos(a) + t * sin(a)) * d
            }
            // arcPoints excludes the θ=1 end; include the final point, drop the start (== end).
            return Array(pts.dropFirst()) + [c + t * d]
        }
    }

    static func segments(radius: Double, tolerance: Double) -> Int {
        let step = 2 * acos(max(-1, min(1, 1 - tolerance / max(radius, tolerance))))
        return max(4, Int(ceil((Double.pi / 2) / max(step, 1e-3))))
    }

    /// Samples f(θ) for θ = 0, 1/n, ..., (n-1)/n.
    static func arcPoints(count n: Int, _ f: (Double) -> Vec2) -> [Vec2] {
        (0..<n).map { f(Double($0) / Double(n)) }
    }
}
