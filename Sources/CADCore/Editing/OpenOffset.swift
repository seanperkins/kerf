import Foundation

/// One-sided offset of an open vector (a parallel copy to its left or right).
public enum OpenOffset {
    /// Parallel copy of open `path` at `distance` to the left of its direction (negative =
    /// right). Corners turning away from the offset side are rounded, others are mitred. The
    /// result is refitted as lines and arcs. Tight curves whose radius is below the distance can
    /// produce loops — the same as offsetting by hand.
    public static func oneSide(_ path: Path, distance d: Double, tolerance: Double) -> Path? {
        guard !path.isClosed, d != 0 else { return nil }
        var pts = path.flattened(tolerance: max(tolerance / 4, 1e-6))
        pts = pts.enumerated().filter { $0.offset == 0 || !$0.element.isApproximatelyEqual(to: pts[$0.offset - 1], tolerance: 1e-12) }.map(\.element)
        guard pts.count >= 2 else { return nil }
        func normal(_ i: Int) -> Vec2 { (pts[i + 1] - pts[i]).normalized.perpendicular }
        var out: [Vec2] = [pts[0] + normal(0) * d]
        for i in 1..<(pts.count - 1) {
            let n0 = normal(i - 1), n1 = normal(i)
            let turn = (pts[i] - pts[i - 1]).cross(pts[i + 1] - pts[i])
            // Offset to the left (d > 0) and a right turn, or vice versa: the corner opens up.
            if turn * d < -1e-15 {
                let v0 = n0 * d, v1 = n1 * d
                let a0 = atan2(v0.y, v0.x)
                var sweep = atan2(v1.y, v1.x) - a0
                while sweep > .pi { sweep -= 2 * .pi }
                while sweep <= -.pi { sweep += 2 * .pi }
                let r = abs(d)
                let step = 2 * acos(max(-1, 1 - min(tolerance, r) / r))
                let steps = max(1, Int((abs(sweep) / max(step, 1e-3)).rounded(.up)))
                for k in 0...steps {
                    let a = a0 + sweep * Double(k) / Double(steps)
                    out.append(pts[i] + Vec2(cos(a), sin(a)) * r)
                }
            } else {
                // Mitre: intersection of the two offset lines (falls back to the vertex normal).
                let p0 = pts[i - 1] + n0 * d, p1 = pts[i] + n1 * d
                let dir0 = pts[i] - pts[i - 1], dir1 = pts[i + 1] - pts[i]
                let den = dir0.cross(dir1)
                if abs(den) < 1e-12 {
                    out.append(pts[i] + n1 * d)
                } else {
                    let t = (p1 - p0).cross(dir1) / den
                    out.append(p0 + dir0 * t)
                }
            }
        }
        out.append(pts[pts.count - 1] + normal(pts.count - 2) * d)
        return CurveFit.fit(Path(points: out, closed: false), tolerance: tolerance)
    }
}
