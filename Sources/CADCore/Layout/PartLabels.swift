import Foundation

/// Where to put a label on a part: the point of the part's material furthest from every edge
/// (outline, holes and features), found by a refined grid search.
public enum PartLabels {
    /// - Parameters:
    ///   - region: closed loops, even-odd (material = inside an odd number of loops).
    ///   - obstacles: extra open polylines the label must keep away from (engraved lines…).
    /// - Returns: the point and its clearance (distance to the nearest edge), nil if the
    ///   region is empty.
    public static func labelPoint(region: [[Vec2]], obstacles: [[Vec2]] = []) -> (point: Vec2, clearance: Double)? {
        var box = Rect2.empty
        for l in region { for v in l { box.include(v) } }
        guard !box.isEmpty, box.width > 0, box.height > 0 else { return nil }
        var segments: [(Vec2, Vec2)] = []
        for l in region where l.count > 1 {
            for i in l.indices { segments.append((l[i], l[(i + 1) % l.count])) }
        }
        for l in obstacles where l.count > 1 {
            for i in 0..<(l.count - 1) { segments.append((l[i], l[i + 1])) }
        }
        func inside(_ p: Vec2) -> Bool {
            var n = false
            for l in region where l.count > 2 && PathGeometry.contains(l, p) { n.toggle() }
            return n
        }
        func clearance(_ p: Vec2) -> Double {
            var best = Double.infinity
            for (a, b) in segments {
                let ab = b - a
                let len2 = ab.dot(ab)
                let t = len2 > 0 ? max(0, min(1, (p - a).dot(ab) / len2)) : 0
                best = min(best, p.distance(to: a + ab * t))
            }
            return best
        }

        var best: (Vec2, Double)?
        var centre = box.center
        var half = Vec2(box.width / 2, box.height / 2)
        let n = 24
        for _ in 0..<5 {
            for j in 0...n {
                for i in 0...n {
                    let p = Vec2(centre.x - half.x + 2 * half.x * Double(i) / Double(n),
                                 centre.y - half.y + 2 * half.y * Double(j) / Double(n))
                    guard inside(p) else { continue }
                    let c = clearance(p)
                    if best == nil || c > best!.1 { best = (p, c) }
                }
            }
            guard let b = best else { return nil }
            centre = b.0
            half = half * (2.5 / Double(n))
        }
        return best.map { (point: $0.0, clearance: $0.1) }
    }
}
