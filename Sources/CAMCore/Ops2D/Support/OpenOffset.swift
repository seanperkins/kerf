import CADCore
import Foundation

/// One-sided offset of an open polyline: the tool-centre path that keeps the cutter on the left
/// or right of the vector (relative to its drawn direction).
public enum OpenOffset {
    /// Returns the offset polyline running in the same direction as `polyline`, or nil when the
    /// offset cannot be traced (e.g. the vector crosses itself or folds back within `distance`).
    public static func oneSided(_ polyline: [Vec2], distance d: Double, left: Bool, tolerance: Double) -> [Vec2]? {
        guard polyline.count > 1, d > tolerance else { return d <= tolerance ? polyline : nil }
        let n0 = (polyline[1] - polyline[0]).normalized.perpendicular
        let n1 = (polyline[polyline.count - 1] - polyline[polyline.count - 2]).normalized.perpendicular
        let sign: Double = left ? 1 : -1
        let start = polyline[0] + n0 * (d * sign)
        let end = polyline[polyline.count - 1] + n1 * (d * sign)
        // Outline at `d` around the polyline with flat (butt) ends; its outer loop is CCW.
        let outline = GeomKernel.offset([polyline], by: d, join: .round, end: .openButt, arcTolerance: tolerance)
        guard let outer = outline.filter({ Polygon2D.signedArea($0) > 0 })
                .max(by: { abs(Polygon2D.signedArea($0)) < abs(Polygon2D.signedArea($1)) }) else { return nil }
        let snap = max(d * 0.01, tolerance * 4)
        func nearest(_ p: Vec2) -> Int? {
            guard let i = outer.indices.min(by: { outer[$0].distance(to: p) < outer[$1].distance(to: p) }),
                  outer[i].distance(to: p) <= snap else { return nil }
            return i
        }
        guard let si = nearest(start), let ei = nearest(end), si != ei else { return nil }
        // Walking the CCW outline, the left side runs from the end back to the start and the right
        // side from the start to the end.
        let (from, to) = left ? (ei, si) : (si, ei)
        var walk: [Vec2] = []
        var i = from
        while true {
            walk.append(outer[i])
            if i == to { break }
            i = (i + 1) % outer.count
        }
        if left { walk.reverse() }
        walk[0] = start
        walk[walk.count - 1] = end
        // Every point must sit at `d` from the vector (otherwise the walk went round an end cap).
        let chain = ArcLengthChain(Chain2D(points: polyline, isClosed: false))
        for p in walk where abs(chain.project(p).distance - d) > snap {
            return nil
        }
        return Polygon2D.deduplicated(walk, closed: false, tolerance: tolerance * 1e-3)
    }
}
