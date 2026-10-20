import CADCore
import Foundation

/// A cleaned, non-self-intersecting polygon set (outer loops + holes) snapped to the
/// Voronoi integer grid. Built from the selected closed vectors with the even-odd rule, so
/// nested contours (the counter of an "O", the hole of an "A") become holes.
struct VCarveRegion {
    /// Clipper output: outers counter-clockwise, holes clockwise; no repeated closing point.
    var polygons: [[Vec2]]
    /// Integer grid used by the Voronoi builder (points per document unit).
    var scale: Double

    static func gridScale(for units: LengthUnit) -> Double { units == .inch ? 10000 : 1000 }

    /// Region from closed shape paths (open paths are ignored by the caller).
    init(paths: [Path], tolerance: Double, units: LengthUnit) {
        let scale = Self.gridScale(for: units)
        let polys = paths.filter(\.isClosed).map { $0.flattened(tolerance: tolerance) }.filter { $0.count > 2 }
        let precision = Int32(log10(scale).rounded())
        let merged = GeomKernel.boolean(.union, subject: polys, clip: [], fillRule: .evenOdd, precision: precision)
        self.init(polygons: merged, scale: scale)
    }

    init(polygons: [[Vec2]], scale: Double) {
        self.scale = scale
        self.polygons = polygons.map { Self.snapped($0, scale: scale) }.filter { $0.count > 2 }
    }

    var isEmpty: Bool { polygons.isEmpty }

    var bounds: Rect2 { Rect2(points: polygons.flatMap { $0 }) }

    /// Polygon edges as Voronoi input segments.
    var segments: [(Vec2, Vec2)] {
        var out: [(Vec2, Vec2)] = []
        for poly in polygons {
            for i in poly.indices { out.append((poly[i], poly[(i + 1) % poly.count])) }
        }
        return out
    }

    /// Even-odd containment test over all loops.
    func contains(_ p: Vec2) -> Bool {
        var inside = false
        for poly in polygons {
            var j = poly.count - 1
            for i in poly.indices {
                let a = poly[i], b = poly[j]
                if (a.y > p.y) != (b.y > p.y) {
                    let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                    if p.x < x { inside.toggle() }
                }
                j = i
            }
        }
        return inside
    }

    /// Inward (negative) or outward (positive) offset with round joins, re-snapped.
    func offset(by delta: Double, arcTolerance: Double) -> VCarveRegion {
        let precision = Int32(log10(scale).rounded())
        let out = GeomKernel.offset(polygons, by: delta, join: .round, arcTolerance: arcTolerance, precision: precision)
        return VCarveRegion(polygons: out, scale: scale)
    }

    /// Rounds to the grid and drops consecutive duplicates (including the closing point).
    static func snapped(_ poly: [Vec2], scale: Double) -> [Vec2] {
        var out: [Vec2] = []
        out.reserveCapacity(poly.count)
        for p in poly {
            let q = Vec2((p.x * scale).rounded() / scale, (p.y * scale).rounded() / scale)
            if let last = out.last, last == q { continue }
            out.append(q)
        }
        while out.count > 1, out.first == out.last { out.removeLast() }
        return out
    }
}
