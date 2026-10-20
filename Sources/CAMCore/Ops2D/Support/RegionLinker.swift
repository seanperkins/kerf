import CADCore
import Foundation

/// Finds a feed-rate link between two points that keeps the tool centre inside a region
/// (so it never gouges a wall or island): a straight move when it stays inside, otherwise a
/// walk along the region boundary when both ends lie on the same boundary loop.
public struct RegionLinker: Sendable {
    public let region: [[Vec2]]
    /// Region grown by `slack` so moves running exactly along the boundary count as inside.
    let grown: [[Vec2]]
    let loops: [ArcLengthChain]
    public let maxLength: Double
    public let slack: Double

    public init(region: [[Vec2]], maxLength: Double, tolerance: Double) {
        self.region = region
        self.maxLength = maxLength
        slack = max(1e-5, tolerance * 0.02)
        grown = GeomKernel.offset(region, by: slack, join: .round, arcTolerance: tolerance)
        loops = region.map { ArcLengthChain(Chain2D(points: $0, isClosed: true)) }
    }

    /// Points to feed through after `a` to arrive at `b` (ending with `b`), or nil when the
    /// tool must retract instead.
    public func link(from a: Vec2, to b: Vec2) -> [Vec2]? {
        let d = a.distance(to: b)
        if d <= slack { return [b] }
        guard d <= maxLength else { return nil }
        if Polygon2D.segmentInside(a, b, region: grown, slack: slack) { return [b] }
        // Boundary walk.
        for loop in loops {
            let pa = loop.project(a), pb = loop.project(b)
            guard pa.distance <= slack * 10, pb.distance <= slack * 10 else { continue }
            let L = loop.length
            var fwd = (pb.s - pa.s).truncatingRemainder(dividingBy: L)
            if fwd < 0 { fwd += L }
            let back = L - fwd
            let (len, end) = fwd <= back ? (fwd, pa.s + fwd) : (back, pa.s - back)
            guard len <= maxLength else { return nil }
            var pts = loop.samples(from: pa.s, to: end) { _ in 0 }.map(\.xy)
            pts.removeFirst()
            if let last = pts.last, last.distance(to: b) > slack { pts.append(b) } else if !pts.isEmpty { pts[pts.count - 1] = b }
            return pts.isEmpty ? [b] : pts
        }
        return nil
    }
}
