import Foundation

/// Pure "select by property" helpers for the Edit > Select menu. Each returns shape IDs in
/// document order; callers decide which shapes are candidates (editable, on the shown side…).
public enum SelectionQueries {
    /// Shapes with at least one open path.
    public static func openVectors(_ shapes: [Shape]) -> [UUID] {
        shapes.filter { s in s.paths.contains { !$0.isClosed && !$0.isEmpty } }.map(\.id)
    }

    /// Later copies of shapes that lie on top of an earlier shape (same outline within
    /// `tolerance`, regardless of start point or direction). The first of each set is kept out of
    /// the result, so deleting the result removes only the extra copies.
    public static func duplicates(_ shapes: [Shape], tolerance: Double) -> [UUID] {
        let info = shapes.map { Outline($0, tolerance: tolerance) }
        let order = info.indices.filter { !info[$0].points.isEmpty }.sorted { info[$0].box.min.x < info[$1].box.min.x }
        // Each shape points at the earliest (document order) shape it duplicates.
        var keeper = Array(info.indices)
        for (oi, a) in order.enumerated() {
            for b in order[(oi + 1)...] {
                if info[b].box.min.x > info[a].box.min.x + tolerance { break }
                let (first, later) = (min(a, b), max(a, b))
                guard keeper[later] == later, info[first].sameGeometry(as: info[later], tolerance: tolerance) else { continue }
                keeper[later] = keeper[first]
            }
        }
        return info.indices.filter { keeper[$0] != $0 }.map { shapes[$0].id }
    }

    /// Shapes the same size and outline as any of `references` (ignoring position): same path
    /// count and open/closed pattern, bounding box, length and area within `relativeTolerance`.
    /// The references themselves are included.
    public static func similar(to references: [Shape], in shapes: [Shape], relativeTolerance: Double = 0.01) -> [UUID] {
        let refs = references.map(Signature.init)
        return shapes.filter { s in
            let sig = Signature(s)
            return refs.contains { $0.matches(sig, relativeTolerance) }
        }.map(\.id)
    }

    /// Candidates not in `selection`.
    public static func inverted(_ selection: Set<UUID>, among candidates: [Shape]) -> [UUID] {
        candidates.map(\.id).filter { !selection.contains($0) }
    }

    // MARK: Helpers

    struct Signature {
        var closedPattern: [Bool]
        var width, height, length, area: Double

        init(_ s: Shape) {
            closedPattern = s.paths.map(\.isClosed).sorted { !$0 && $1 }
            let b = s.bounds()
            width = b.width; height = b.height
            length = s.paths.reduce(0) { $0 + $1.length() }
            area = s.paths.reduce(0) { $0 + ($1.isClosed ? abs($1.signedArea()) : 0) }
        }

        func matches(_ o: Signature, _ rel: Double) -> Bool {
            func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= rel * max(abs(a), abs(b)) + 1e-9 }
            return closedPattern == o.closedPattern && near(width, o.width) && near(height, o.height)
                && near(length, o.length) && near(area, o.area)
        }
    }

    struct Outline {
        var box: Rect2
        /// Flattened polylines, one per path.
        var polylines: [[Vec2]]
        var points: [Vec2] { polylines.flatMap { $0 } }

        init(_ s: Shape, tolerance: Double) {
            box = s.bounds()
            polylines = s.paths.map { p in
                var pts = p.flattened(tolerance: max(tolerance / 4, 1e-6))
                if p.isClosed, let f = pts.first, pts.last != f { pts.append(f) }
                return pts
            }
        }

        func sameGeometry(as o: Outline, tolerance t: Double) -> Bool {
            guard polylines.count == o.polylines.count,
                  box.min.isApproximatelyEqual(to: o.box.min, tolerance: t),
                  box.max.isApproximatelyEqual(to: o.box.max, tolerance: t) else { return false }
            return covers(o, t) && o.covers(self, t)
        }

        /// Every vertex of `o` lies within `t` of this outline.
        func covers(_ o: Outline, _ t: Double) -> Bool {
            o.points.allSatisfy { q in polylines.contains { Self.distance(q, to: $0) <= t } }
        }

        static func distance(_ q: Vec2, to poly: [Vec2]) -> Double {
            guard poly.count > 1 else { return poly.first.map { $0.distance(to: q) } ?? .infinity }
            var best = Double.infinity
            for i in 1..<poly.count {
                let a = poly[i - 1], ab = poly[i] - a, l2 = ab.lengthSquared
                let t = l2 > 0 ? min(max((q - a).dot(ab) / l2, 0), 1) : 0
                best = min(best, q.distance(to: a + ab * t))
                if best == 0 { break }
            }
            return best
        }
    }
}
