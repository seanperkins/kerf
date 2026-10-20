import CADCore
import Foundation

/// Flat-bottom clearing of a V-carve's flat area (self-contained so the V-carve workstream
/// does not depend on the 2D pocket generator).
enum VCarvePocketing {
    /// Strokes clearing `region` at `depth` with a cutter of `toolRadius` whose centre stays
    /// at least `toolRadius` inside the boundary. Offset passes run innermost → boundary.
    static func strokes(region: VCarveRegion, toolRadius: Double, stepover: Double,
                        strategy: PocketStrategy, depth: Double, arcTolerance: Double) -> [VCarveStroke] {
        let step = max(stepover, 1e-4)
        let reach = toolRadius > 1e-9 ? region.offset(by: -toolRadius, arcTolerance: arcTolerance) : region
        guard !reach.isEmpty else { return [] }
        switch strategy {
        case .offset:
            var rings: [[[Vec2]]] = []
            var current = reach
            var guardCount = 0
            while !current.isEmpty, guardCount < 10_000 {
                rings.append(current.polygons)
                current = current.offset(by: -step, arcTolerance: arcTolerance)
                guardCount += 1
            }
            return rings.reversed().flatMap { VCarveStrokes.loops($0, depth: depth) }
        case .raster(let angle, let profilePass):
            var out = raster(reach, angle: angle, step: step, depth: depth)
            if profilePass { out += VCarveStrokes.loops(reach.polygons, depth: depth) }
            return out
        }
    }

    /// Parallel lines at `angle` degrees clipped to the region, alternating direction.
    static func raster(_ region: VCarveRegion, angle: Double, step: Double, depth: Double) -> [VCarveStroke] {
        let b = region.bounds
        let c = b.center
        let half = (b.width * b.width + b.height * b.height).squareRoot() / 2 + step
        let rad = angle * .pi / 180
        let dir = Vec2(cos(rad), sin(rad)), normal = dir.perpendicular
        var lines: [[Vec2]] = []
        var t = -half + step / 2
        while t <= half {
            let o = c + normal * t
            lines.append([o - dir * half, o + dir * half])
            t += step
        }
        let precision = Int32(log10(region.scale).rounded())
        let clipped = GeomKernel.boolean(.intersection, subject: lines, clip: region.polygons,
                                         fillRule: .evenOdd, subjectsOpen: true, precision: precision)
        // Sort along the normal, then along the direction, and zig-zag.
        let sorted = clipped.filter { $0.count >= 2 }.sorted {
            let a = $0[0].dot(normal), b = $1[0].dot(normal)
            return abs(a - b) > step / 4 ? a < b : $0[0].dot(dir) < $1[0].dot(dir)
        }
        var forward = true
        var lastRow = -Double.infinity
        return sorted.map { seg in
            let row = seg[0].dot(normal)
            if abs(row - lastRow) > step / 4 { forward.toggle(); lastRow = row }
            var pts = seg
            if (pts[pts.count - 1].dot(dir) < pts[0].dot(dir)) == forward { pts.reverse() }
            return VCarveStroke(points: pts.map { Vec3($0, z: depth) }, isClosed: false)
        }
    }
}
