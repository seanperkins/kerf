import CADCore
import Foundation

/// Medial axis of a `VCarveRegion`: the primary Voronoi edges of the boundary segments that
/// lie strictly inside the region, chained into continuous polylines. Every point carries
/// its inscribed-circle radius (distance to the nearest boundary).
struct VCarveMedialAxis {
    struct Point: Hashable {
        var position: Vec2
        var radius: Double
    }

    /// Chained polylines in a cutting-friendly order (long continuous walks, few lifts).
    var chains: [[Point]]

    init(region: VCarveRegion, sampleStep: Double) {
        guard !region.isEmpty else { chains = []; return }
        let vd = GeomKernel.voronoi(segments: region.segments, scale: region.scale, maxSampleStep: sampleStep)
        let minRadius = 0.5 / region.scale

        // One half-edge per undirected edge, primary, finite and inside the region.
        var edges: [(v0: Int, v1: Int, points: [Point])] = []
        for (i, e) in vd.edges.enumerated() where i < e.twin && e.isPrimary {
            guard let v0 = e.vertex0, let v1 = e.vertex1 else { continue }
            let samples = vd.samples(of: e)
            guard samples.count >= 2 else { continue }
            let mid: Vec2
            let midRadius: Double
            if samples.count == 2 {
                let a = samples[samples.startIndex], b = samples[samples.startIndex + 1]
                mid = a.position.lerp(to: b.position, 0.5)
                midRadius = max(a.radius, b.radius)
            } else {
                let m = samples[samples.startIndex + samples.count / 2]
                mid = m.position
                midRadius = m.radius
            }
            guard midRadius > minRadius, region.contains(mid) else { continue }
            edges.append((v0, v1, samples.map { Point(position: $0.position, radius: $0.radius) }))
        }
        chains = Self.chain(edges)
    }

    /// Walks the edge graph: continue through vertices while unvisited edges remain
    /// (preferring the straightest continuation), then jump to the nearest loose end.
    private static func chain(_ edges: [(v0: Int, v1: Int, points: [Point])]) -> [[Point]] {
        var adjacency: [Int: [Int]] = [:]
        for (i, e) in edges.enumerated() {
            adjacency[e.v0, default: []].append(i)
            adjacency[e.v1, default: []].append(i)
        }
        var visited = [Bool](repeating: false, count: edges.count)
        var remaining = edges.count
        var unvisitedDegree: [Int: Int] = adjacency.mapValues(\.count)
        var nodePosition: [Int: Vec2] = [:]
        for e in edges {
            nodePosition[e.v0] = e.points.first!.position
            nodePosition[e.v1] = e.points.last!.position
        }

        var chains: [[Point]] = []
        var cursor = Vec2.zero
        while remaining > 0 {
            // Pick a start node: nearest odd-degree (dead end) node, else nearest any.
            var best: (node: Int, score: Double)?
            for (node, deg) in unvisitedDegree where deg > 0 {
                let d = nodePosition[node]!.distance(to: cursor) + (deg % 2 == 1 ? 0 : 1e6)
                if best == nil || d < best!.score { best = (node, d) }
            }
            guard var node = best?.node else { break }
            var chain: [Point] = []
            var heading: Vec2?
            while true {
                let candidates = adjacency[node]!.filter { !visited[$0] }
                guard !candidates.isEmpty else { break }
                func direction(_ i: Int) -> Vec2 {
                    let pts = edges[i].v0 == node ? edges[i].points : edges[i].points.reversed()
                    let far = pts[min(pts.count - 1, max(1, pts.count / 4))].position
                    return (far - pts[0].position).normalized
                }
                let next = heading.map { h in candidates.max { direction($0).dot(h) < direction($1).dot(h) }! }
                    ?? candidates[0]
                visited[next] = true
                remaining -= 1
                let e = edges[next]
                unvisitedDegree[e.v0]! -= 1
                unvisitedDegree[e.v1]! -= 1
                let pts = e.v0 == node ? e.points : e.points.reversed()
                chain.append(contentsOf: chain.isEmpty ? pts[...] : pts.dropFirst())
                if pts.count >= 2 { heading = (pts[pts.count - 1].position - pts[pts.count - 2].position).normalized }
                node = e.v0 == node ? e.v1 : e.v0
            }
            if chain.count >= 2 { chains.append(chain) }
            if let last = chain.last { cursor = last.position }
        }
        return chains
    }
}
