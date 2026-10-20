import CADCore
import Foundation

/// User-selected cutting order for profile loops (parts). Inner loops are always cut before the
/// loop that contains them, and every loop is ranked by the outermost loop around it, so a part's
/// holes are cut together with the part.
public enum ProfileOrdering {
    /// - Parameters:
    ///   - shapeLoops: flattened loops of each selected vector, in selection order (for `.selection`).
    ///   - allowReverse: open chains may be reversed to start at their nearer end.
    public static func ordered(_ chains: [Chain2D], by order: ProfileOrder, from start: Vec2,
                               shapeLoops: [[[Vec2]]], allowReverse: Bool, tolerance: Double) -> [Chain2D] {
        let preds = ChainOrdering.innerFirstPredecessors(chains)
        guard order != .nearest, chains.count > 1 else {
            return ChainOrdering.nearestNeighbour(chains, from: start, allowReverse: allowReverse,
                                                  predecessors: preds, tolerance: tolerance)
        }
        // Outermost loop containing each chain (itself when none does).
        let outermost: [Int] = chains.indices.map { i in
            var best = i
            var bestArea = chains[i].isClosed ? abs(Polygon2D.signedArea(chains[i].points)) : 0
            for j in chains.indices where preds[j].contains(i) {
                let a = abs(Polygon2D.signedArea(chains[j].points))
                if a > bestArea { bestArea = a; best = j }
            }
            return best
        }
        let boxes = chains.map { Rect2(points: $0.points) }
        func centre(_ i: Int) -> Vec2 { Vec2((boxes[i].min.x + boxes[i].max.x) / 2, (boxes[i].min.y + boxes[i].max.y) / 2) }
        let partKey: [Double]
        switch order {
        case .nearest:
            partKey = chains.indices.map(Double.init)
        case .selection:
            partKey = chains.indices.map { i in
                let p = chains[i].points.first ?? .zero
                let k = shapeLoops.indices.min { a, b in
                    distance(p, shapeLoops[a]) < distance(p, shapeLoops[b])
                }
                return Double(k ?? 0)
            }
        case .leftToRight:
            partKey = chains.indices.map { boxes[$0].min.x }
        case .bottomToTop:
            partKey = chains.indices.map { boxes[$0].min.y }
        case .grid:
            // Rows from the bottom (row height = median part height), left to right in each row.
            let parts = Array(Set(outermost))
            let heights = parts.map { boxes[$0].height }.sorted()
            let band = max(heights.isEmpty ? 1 : heights[heights.count / 2], tolerance * 10)
            let minY = parts.map { centre($0).y }.min() ?? 0
            let minX = parts.map { boxes[$0].min.x }.min() ?? 0
            let spanX = (parts.map { boxes[$0].max.x }.max() ?? 0) - minX + 1
            partKey = chains.indices.map { i in
                let row = ((centre(i).y - minY) / band + 0.5).rounded(.down)
                return row * spanX + (boxes[i].min.x - minX)
            }
        }
        // Rank by the part key, then inner loops (smaller) first within a part.
        let rank = chains.indices.sorted { a, b in
            let ka = partKey[outermost[a]], kb = partKey[outermost[b]]
            if abs(ka - kb) > 1e-9 { return ka < kb }
            if outermost[a] != outermost[b] { return outermost[a] < outermost[b] }
            return boxes[a].width * boxes[a].height < boxes[b].width * boxes[b].height
        }
        var done = Set<Int>()
        var out: [Chain2D] = []
        var cur = start
        while done.count < chains.count {
            let i = rank.first { !done.contains($0) && preds[$0].isSubset(of: done) }
                ?? rank.first { !done.contains($0) }!
            done.insert(i)
            var c = chains[i]
            if c.isClosed {
                c.points = Polygon2D.rotatedLoop(c.points, nearestTo: cur, tolerance: tolerance)
            } else if allowReverse, c.end.distance(to: cur) < c.start.distance(to: cur) {
                c = c.reversed()
            }
            out.append(c)
            cur = c.end
        }
        return out
    }

    private static func distance(_ p: Vec2, _ loops: [[Vec2]]) -> Double {
        loops.map { $0.count > 2 ? Polygon2D.distance(from: p, toLoop: $0) : ($0.first?.distance(to: p) ?? .infinity) }
            .min() ?? .infinity
    }
}
