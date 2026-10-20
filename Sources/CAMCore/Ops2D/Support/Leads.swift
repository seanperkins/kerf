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

    /// Lead-in that stays in the waste: tries the configured lead, then straight approaches
    /// (diagonal back, diagonal forward, pure normal), shrinking the length until every point
    /// of the lead satisfies `isWaste`. Returns no lead when nothing fits (e.g. a sharp inside
    /// corner where the configured lead would back through the wall).
    public static func safeLeadIn(to start: Vec2, tangent t: Vec2, waste n: Vec2, settings: LeadSettings,
                                  tolerance: Double, isWaste: (Vec2) -> Bool) -> [Vec2] {
        fitted(anchor: start, settings: settings, candidates: [n - t, n + t, n], isWaste: isWaste) { s in
            leadIn(to: start, tangent: t, waste: n, settings: s, tolerance: tolerance)
        }
    }

    /// Lead-out counterpart of `safeLeadIn`.
    public static func safeLeadOut(from end: Vec2, tangent t: Vec2, waste n: Vec2, settings: LeadSettings,
                                   tolerance: Double, isWaste: (Vec2) -> Bool) -> [Vec2] {
        fitted(anchor: end, settings: settings, candidates: [n + t, n - t, n], isWaste: isWaste) { s in
            leadOut(from: end, tangent: t, waste: n, settings: s, tolerance: tolerance)
        }
    }

    private static func fitted(anchor: Vec2, settings: LeadSettings, candidates: [Vec2],
                               isWaste: (Vec2) -> Bool, configured: (LeadSettings) -> [Vec2]) -> [Vec2] {
        guard settings.type != .none, settings.distance > 0 else { return [] }
        for scale in [1.0, 0.5, 0.25, 0.125] {
            var s = settings
            s.distance = settings.distance * scale
            let pts = configured(s)
            if allWaste(anchor: anchor, pts, isWaste) { return pts }
            for c in candidates where c.length > 1e-12 {
                let lp = [anchor + c.normalized * s.distance]
                if allWaste(anchor: anchor, lp, isWaste) { return lp }
            }
        }
        return []
    }

    /// Samples the polyline anchor → pts (excluding the anchor itself).
    private static func allWaste(anchor: Vec2, _ pts: [Vec2], _ isWaste: (Vec2) -> Bool) -> Bool {
        var prev = anchor
        for q in pts {
            for k in 1...16 where !isWaste(prev + (q - prev) * (Double(k) / 16)) { return false }
            prev = q
        }
        return true
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
