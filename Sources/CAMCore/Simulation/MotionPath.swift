import CADCore
import Foundation

/// A straight piece of tool motion in machine coordinates. Arcs are flattened into several.
public struct MotionSegment: Hashable, Sendable {
    public var start: Vec3
    public var end: Vec3
    public var isRapid: Bool
    /// Feed in units/min (nil for rapids).
    public var feed: Double?
    /// Index of the originating `Move` in its toolpath.
    public var moveIndex: Int

    public init(start: Vec3, end: Vec3, isRapid: Bool, feed: Double?, moveIndex: Int) {
        self.start = start; self.end = end; self.isRapid = isRapid; self.feed = feed
        self.moveIndex = moveIndex
    }

    public var length: Double { start.distance(to: end) }

    public func point(at t: Double) -> Vec3 {
        Vec3(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t,
             start.z + (end.z - start.z) * t)
    }
}

/// Flattens `Move` lists into straight `MotionSegment`s (arcs/helices by chord tolerance).
public enum MotionPath {
    /// - Parameter start: tool position before the first move; when nil, the first move's
    ///   target is taken as the starting point (it yields no segment).
    public static func segments(of moves: [Move], startingAt start: Vec3? = nil,
                                arcTolerance: Double = 0.001) -> [MotionSegment] {
        var out: [MotionSegment] = []
        var pos = start
        for (k, move) in moves.enumerated() {
            guard let target = move.target else { continue }
            guard let from = pos else { pos = target; continue }
            switch move {
            case .rapid:
                out.append(MotionSegment(start: from, end: target, isRapid: true, feed: nil, moveIndex: k))
            case .linear(_, let feed):
                out.append(MotionSegment(start: from, end: target, isRapid: false, feed: feed, moveIndex: k))
            case .arcCW(_, let c, let feed):
                appendArc(from: from, to: target, center: c, clockwise: true, feed: feed,
                          moveIndex: k, tolerance: arcTolerance, into: &out)
            case .arcCCW(_, let c, let feed):
                appendArc(from: from, to: target, center: c, clockwise: false, feed: feed,
                          moveIndex: k, tolerance: arcTolerance, into: &out)
            case .dwell:
                break
            }
            pos = target
        }
        return out
    }

    static func appendArc(from: Vec3, to: Vec3, center: Vec2, clockwise: Bool, feed: Double,
                          moveIndex: Int, tolerance: Double, into out: inout [MotionSegment]) {
        let r = (from.xy - center).length
        guard r > 1e-12 else {
            out.append(MotionSegment(start: from, end: to, isRapid: false, feed: feed, moveIndex: moveIndex))
            return
        }
        let sweep = Flattening.arcSweep(from: from.xy, to: to.xy, center: center, clockwise: clockwise)
        let tol = max(tolerance, 1e-6)
        let maxStep = r > tol ? 2 * acos(max(-1, 1 - tol / r)) : Double.pi / 2
        let n = max(1, min(10_000, Int(ceil(abs(sweep) / max(maxStep, 1e-6)))))
        let a0 = (from.xy - center).angle
        // The end radius may differ slightly from the start radius (rounding); blend linearly.
        let r1 = (to.xy - center).length
        var prev = from
        for i in 1...n {
            let t = Double(i) / Double(n)
            let p: Vec3
            if i == n {
                p = to
            } else {
                let a = a0 + sweep * t
                let rr = r + (r1 - r) * t
                p = Vec3(center.x + cos(a) * rr, center.y + sin(a) * rr, from.z + (to.z - from.z) * t)
            }
            out.append(MotionSegment(start: prev, end: p, isRapid: false, feed: feed, moveIndex: moveIndex))
            prev = p
        }
    }
}
