import CADCore
import Foundation

/// V-bit engraving along vectors (sketch carving): the bit follows the vector itself at a
/// constant depth, or with depth easing in from the surface over `taper` of the length at
/// each end so strokes start and finish as fine points.
enum VCarveEngraving {
    /// - Parameters:
    ///   - depth: full depth below `startDepth`.
    ///   - taper: fraction of the vector length (0…0.5) over which each end rises to the surface.
    ///   - step: maximum spacing of the sampled points in tapered sections.
    static func stroke(_ path: Path, startDepth: Double, depth: Double, taper: Double, tolerance: Double,
                       step: Double) -> VCarveStroke? {
        var pts = path.flattened(tolerance: tolerance)
        if path.isClosed, let first = pts.first, pts.last != first { pts.append(first) }
        guard pts.count >= 2 else { return nil }
        let t = min(max(taper, 0), 0.5)
        guard t > 1e-9 else {
            return VCarveStroke(points: pts.map { Vec3($0, z: startDepth + depth) }, isClosed: path.isClosed)
        }
        // Densify so the depth profile is followed between widely spaced vertices.
        var dense: [Vec2] = [pts[0]]
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let n = max(1, Int((a.distance(to: b) / max(step, 1e-6)).rounded(.up)))
            for k in 1...n { dense.append(a.lerp(to: b, Double(k) / Double(n))) }
        }
        var s = [0.0]
        for i in 1..<dense.count { s.append(s[i - 1] + dense[i - 1].distance(to: dense[i])) }
        let total = s[s.count - 1]
        guard total > 1e-9 else { return nil }
        let ramp = t * total
        let out = dense.indices.map { i -> Vec3 in
            let u = min(1, min(s[i], total - s[i]) / ramp)
            return Vec3(dense[i], z: startDepth + depth * (1 - cos(.pi * u)) / 2)
        }
        // A tapered closed vector starts and ends at the surface, so it is cut as an open stroke.
        return VCarveStroke(points: out, isClosed: false)
    }
}
