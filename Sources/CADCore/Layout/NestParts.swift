import Foundation

/// A part to nest: the shapes that move together and their combined outline.
public struct NestPartGroup: Hashable, Sendable {
    public var shapeIDs: [UUID]
    /// Closed polygons (even-odd) of the part's material, in design coordinates.
    public var outline: [[Vec2]]
}

/// Turns a selection of shapes into nestable parts. Grouped shapes form one part, and any
/// shape lying inside another part's outer outline (holes, pockets, text, drill marks) travels
/// with that part, so a part keeps all its features when it is moved or rotated.
public enum NestPartBuilder {
    public static func parts(from shapes: [Shape], tolerance: Double = Path.defaultTolerance) -> [NestPartGroup] {
        // 1. Clusters: one per group, one per loose shape.
        var clusters: [[Shape]] = []
        var groupIndex: [UUID: Int] = [:]
        for s in shapes {
            if let g = s.groupID {
                if let i = groupIndex[g] { clusters[i].append(s); continue }
                groupIndex[g] = clusters.count
            }
            clusters.append([s])
        }

        // 2. Outline of each cluster: filled closed shapes, or a thin band around open paths.
        let outlines: [[[Vec2]]] = clusters.map { outline(of: $0, tolerance: tolerance) }
        let outers: [[[Vec2]]] = outlines.map { loops in
            let d = NestPart.depths(loops)
            return zip(loops, d).filter { $0.1 == 0 }.map(\.0)
        }
        let areas = outers.map { $0.reduce(0) { $0 + abs(PathGeometry.area($1)) } }
        let boxes = outlines.map { Rect2(points: $0.joined()) }

        // 3. Attach each cluster to the largest cluster whose outer outline contains it.
        var owner = Array(clusters.indices)
        for i in clusters.indices {
            guard let probe = probePoint(clusters[i], tolerance: tolerance), !boxes[i].isEmpty else { continue }
            var best: Int?
            for j in clusters.indices where j != i && areas[j] > areas[i] + 1e-12 {
                let bj = boxes[j]
                guard bj.contains(boxes[i].min), bj.contains(boxes[i].max) else { continue }
                if outers[j].contains(where: { PathGeometry.contains($0, probe) }),
                   best.map({ areas[j] > areas[$0] }) ?? true {
                    best = j
                }
            }
            if let b = best { owner[i] = b }
        }

        var result: [NestPartGroup] = []
        var resultIndex: [Int: Int] = [:]
        for i in clusters.indices {
            let o = owner[i]
            if let r = resultIndex[o] {
                result[r].shapeIDs += clusters[i].map(\.id)
                if o == i { result[r].outline = outlines[i] }
            } else {
                resultIndex[o] = result.count
                result.append(NestPartGroup(shapeIDs: clusters[i].map(\.id), outline: outlines[o]))
            }
        }
        // Owners listed before their members keep the owner's outline; members never widen it
        // (they lie inside). Order follows the first shape of each part in the input.
        return result
    }

    static func outline(of shapes: [Shape], tolerance: Double) -> [[Vec2]] {
        var regions: [[Vec2]] = []
        for s in shapes {
            let closed = s.paths.filter(\.isClosed).map { $0.flattened(tolerance: tolerance) }.filter { $0.count > 2 }
            if !closed.isEmpty {
                regions += GeomKernel.boolean(.union, subject: closed, clip: [], fillRule: .evenOdd)
            }
            let open = s.paths.filter { !$0.isClosed }.map { $0.flattened(tolerance: tolerance) }.filter { $0.count > 1 }
            if !open.isEmpty {
                regions += GeomKernel.offset(open, by: max(tolerance, 1e-4), join: .round, end: .openRound)
            }
        }
        guard regions.count > 1 else { return regions }
        return GeomKernel.boolean(.union, subject: regions, clip: [])
    }

    private static func probePoint(_ shapes: [Shape], tolerance: Double) -> Vec2? {
        for s in shapes { for p in s.paths where !p.isEmpty { return p.start } }
        return nil
    }
}
