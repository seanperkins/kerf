import CADCore
import Foundation

/// A chain parameterised by arc length `s`. For closed loops `s` is "unwrapped": values past
/// `length` continue around the loop again (so a pass can overlap its start).
public struct ArcLengthChain: Sendable {
    public let chain: Chain2D
    /// Walk vertices (closed loops repeat the first point at the end).
    let walk: [Vec2]
    /// Cumulative arc length at each walk vertex.
    let cumulative: [Double]

    public init(_ chain: Chain2D) {
        self.chain = chain
        walk = chain.walk
        var c = [0.0]
        for (a, b) in zip(walk, walk.dropFirst()) { c.append(c.last! + a.distance(to: b)) }
        cumulative = c
    }

    public var length: Double { cumulative.last ?? 0 }
    public var isClosed: Bool { chain.isClosed }

    /// Wraps an unwrapped parameter into [0, length) for closed loops; clamps for open chains.
    func local(_ s: Double) -> Double {
        let L = length
        guard L > 0 else { return 0 }
        if isClosed {
            let r = s.truncatingRemainder(dividingBy: L)
            return r < 0 ? r + L : r
        }
        return min(max(s, 0), L)
    }

    public func point(at s: Double) -> Vec2 {
        guard walk.count > 1 else { return walk.first ?? .zero }
        let u = local(s)
        // Binary search for the segment containing u.
        var lo = 0, hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= u { lo = mid } else { hi = mid }
        }
        let segLen = cumulative[hi] - cumulative[lo]
        let t = segLen > 0 ? (u - cumulative[lo]) / segLen : 0
        return walk[lo].lerp(to: walk[hi], t)
    }

    /// Unit tangent at `s` (direction of travel for increasing s).
    public func tangent(at s: Double) -> Vec2 {
        let L = length
        guard L > 0 else { return Vec2(1, 0) }
        let h = min(L * 1e-4, 1e-4)
        var a = point(at: s), b = point(at: s + h)
        if !isClosed, s + h > L { a = point(at: s - h); b = point(at: s) }
        let d = b - a
        return d.length > 0 ? d.normalized : Vec2(1, 0)
    }

    /// Parameter (in [0, length]) and distance of the point on the chain closest to `q`.
    public func project(_ q: Vec2) -> (s: Double, distance: Double) {
        var best = (s: 0.0, distance: Double.infinity)
        for i in 0..<max(walk.count - 1, 0) {
            let (c, t) = Polygon2D.closestPoint(onSegment: walk[i], walk[i + 1], to: q)
            let d = c.distance(to: q)
            if d < best.distance { best = (cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), d) }
        }
        return best
    }

    /// Unwrapped parameters of all walk vertices strictly between s0 and s1 (s0 < s1).
    func vertexParameters(between s0: Double, and s1: Double) -> [Double] {
        let L = length
        guard L > 0, s1 > s0 else { return [] }
        if !isClosed {
            return cumulative.filter { $0 > s0 && $0 < s1 }
        }
        var out: [Double] = []
        var lap = (s0 / L).rounded(.down)
        while lap * L < s1 {
            for c in cumulative.dropLast() {
                let s = lap * L + c
                if s > s0 && s < s1 { out.append(s) }
            }
            lap += 1
        }
        return out
    }

    /// Samples from s0 to s1 (either direction) at every vertex plus the given extra
    /// parameters, with depth from `depth(s)`.
    public func samples(from s0: Double, to s1: Double, extraBreaks: [Double] = [],
                        depth: (Double) -> Double) -> [StationPoint] {
        let lo = min(s0, s1), hi = max(s0, s1)
        var params = [lo] + vertexParameters(between: lo, and: hi) + extraBreaks.filter { $0 > lo && $0 < hi } + [hi]
        params.sort()
        var out: [StationPoint] = []
        out.reserveCapacity(params.count)
        for s in params where out.last.map({ s - $0.s > 1e-12 }) ?? true {
            out.append(StationPoint(xy: point(at: s), s: s, depth: depth(s)))
        }
        if out.count == 1, hi > lo { out.append(StationPoint(xy: point(at: hi), s: hi, depth: depth(hi))) }
        return s1 < s0 ? out.reversed() : out
    }
}

/// A sample along an `ArcLengthChain`.
public struct StationPoint: Hashable, Sendable {
    public var xy: Vec2
    public var s: Double
    public var depth: Double

    public var cutPoint: CutPoint { CutPoint(xy, depth: depth) }
}
