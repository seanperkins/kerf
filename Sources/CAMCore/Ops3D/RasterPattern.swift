import CADCore
import Foundation

/// Parallel raster lines at an angle, clipped to closed region polygons (even-odd, so holes
/// work). Lines span the region edge to edge so the tool centre reaches the boundary.
struct RasterPattern {
    struct Segment { var start: Vec2; var end: Vec2 }

    /// Unit direction of the lines.
    let direction: Vec2
    /// One entry per raster line (in order across the region); each holds that line's clipped
    /// segments ordered along `direction`.
    let lines: [[Segment]]

    init(region: [[Vec2]], angleDegrees: Double, spacing: Double) {
        let a = angleDegrees * .pi / 180
        let dir = Vec2(cos(a), sin(a))
        let nrm = dir.perpendicular
        direction = dir
        let pts = region.flatMap { $0 }
        guard pts.count >= 3, spacing > 0 else { lines = []; return }
        let ss = pts.map { $0.dot(nrm) }, ts = pts.map { $0.dot(dir) }
        let sMin = ss.min()!, sMax = ss.max()!
        let tMin = ts.min()! - 1, tMax = ts.max()! + 1
        let span = sMax - sMin
        let n = max(1, Int(ceil(span / spacing - 1e-9)))
        // Inset the outermost lines a hair so they do not graze a boundary edge exactly
        // (Clipper's result for collinear open paths is ill-defined).
        let inset = min(span * 1e-6, 1e-6)
        var out: [[Segment]] = []
        for k in 0...n {
            let s = span < 1e-12 ? sMin : sMin + inset + (span - 2 * inset) * Double(k) / Double(n)
            let p0 = nrm * s + dir * tMin, p1 = nrm * s + dir * tMax
            let clipped = GeomKernel.boolean(.intersection, subject: [[p0, p1]], clip: region,
                                             fillRule: .evenOdd, subjectsOpen: true)
            var segs: [Segment] = []
            for c in clipped where c.count >= 2 {
                var a = c.first!, b = c.last!
                if a.dot(dir) > b.dot(dir) { swap(&a, &b) }
                if a.distance(to: b) > 1e-9 { segs.append(Segment(start: a, end: b)) }
            }
            segs.sort { $0.start.dot(dir) < $1.start.dot(dir) }
            if !segs.isEmpty { out.append(segs) }
            if span < 1e-12 { break }
        }
        lines = out
    }

    /// Segments in zig-zag cutting order: odd lines are reversed (segments and their order).
    var zigzag: [Segment] {
        lines.enumerated().flatMap { k, segs -> [Segment] in
            k % 2 == 0 ? segs : segs.reversed().map { Segment(start: $0.end, end: $0.start) }
        }
    }
}

enum ReliefRegion {
    /// Closed, flattened boundary polygons of the given shapes.
    static func polygons(of shapes: [Shape], tolerance: Double) -> [[Vec2]] {
        shapes.flatMap { $0.paths }.filter(\.isClosed).map { $0.flattened(tolerance: tolerance) }
            .filter { $0.count >= 3 }
    }

    static func rectangle(_ r: Rect2) -> [Vec2] {
        [r.min, Vec2(r.max.x, r.min.y), r.max, Vec2(r.min.x, r.max.y)]
    }
}
