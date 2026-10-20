import Foundation

/// A problem with a design vector that can break or surprise toolpath generation.
public struct VectorIssue: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// Path (or whole shape) with no length.
        case zeroLength
        /// Segments that start and end at the same point.
        case zeroLengthSegments
        /// Open path whose ends almost meet (should probably be closed).
        case nearlyClosed
        /// Open path: profiles cut it on the line; pockets and V-carves ignore it.
        case open
        /// Path lying on top of another path (duplicate or overlapping copy).
        case duplicate
        /// Path that crosses itself.
        case selfIntersecting

        public var title: String {
            switch self {
            case .zeroLength: return "Zero-length vector"
            case .zeroLengthSegments: return "Zero-length segments"
            case .nearlyClosed: return "Nearly closed vector"
            case .open: return "Open vector"
            case .duplicate: return "Duplicate / overlapping vector"
            case .selfIntersecting: return "Self-intersecting vector"
            }
        }

        /// True when `VectorValidator.fix` can repair it automatically.
        public var isFixable: Bool { self != .open }
    }

    public var kind: Kind
    public var shapeID: UUID
    /// Path index within the shape (nil = the whole shape).
    public var pathIndex: Int?
    /// Where to look (crossing point, gap, …).
    public var location: Vec2?
    /// For duplicates: the shape the path lies on.
    public var otherShapeID: UUID?

    public init(kind: Kind, shapeID: UUID, pathIndex: Int?, location: Vec2? = nil, otherShapeID: UUID? = nil) {
        self.kind = kind; self.shapeID = shapeID; self.pathIndex = pathIndex
        self.location = location; self.otherShapeID = otherShapeID
    }
}

/// Checks design vectors for open, nearly closed, duplicate, self-intersecting and zero-length
/// geometry, and repairs what can be repaired.
public enum VectorValidator {
    /// `tolerance` is the distance under which points count as the same (document units).
    public static func check(_ shapes: [Shape], tolerance: Double, includeOpen: Bool = true) -> [VectorIssue] {
        var out: [VectorIssue] = []
        let flatTol = max(tolerance / 4, 1e-6)
        for s in shapes {
            if s.paths.isEmpty { out.append(VectorIssue(kind: .zeroLength, shapeID: s.id, pathIndex: nil)); continue }
            for (i, p) in s.paths.enumerated() {
                let poly = p.flattened(tolerance: flatTol)
                if p.isEmpty || p.length(tolerance: flatTol) <= tolerance {
                    out.append(VectorIssue(kind: .zeroLength, shapeID: s.id, pathIndex: i, location: p.start))
                    continue
                }
                if let k = zeroSegmentIndices(p, tolerance: tolerance).first {
                    out.append(VectorIssue(kind: .zeroLengthSegments, shapeID: s.id, pathIndex: i, location: p.startOfSegment(k)))
                }
                if !p.isClosed {
                    let gap = p.start.distance(to: p.end)
                    let nearly = gap <= max(tolerance * 20, 1e-6) && poly.count > 2
                    if nearly {
                        out.append(VectorIssue(kind: .nearlyClosed, shapeID: s.id, pathIndex: i, location: p.end))
                    } else if includeOpen {
                        out.append(VectorIssue(kind: .open, shapeID: s.id, pathIndex: i, location: p.end))
                    }
                }
                if let x = selfIntersection(poly, closed: p.isClosed, tolerance: tolerance) {
                    out.append(VectorIssue(kind: .selfIntersecting, shapeID: s.id, pathIndex: i, location: x))
                }
            }
        }
        out += duplicates(shapes, tolerance: tolerance)
        return out
    }

    /// Paths lying on top of other paths. For two identical paths the later one is reported;
    /// a path covered by a longer one is reported, the longer one is not.
    public static func duplicates(_ shapes: [Shape], tolerance: Double) -> [VectorIssue] {
        struct Item { var shape: UUID; var path: Int; var poly: [Vec2]; var box: Rect2; var length: Double }
        let flatTol = max(tolerance / 4, 1e-6)
        var items: [Item] = []
        for s in shapes {
            for (i, p) in s.paths.enumerated() where !p.isEmpty {
                var poly = p.flattened(tolerance: flatTol)
                if p.isClosed, let f = poly.first { poly.append(f) }
                guard poly.count >= 2 else { continue }
                let len = zip(poly, poly.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
                guard len > tolerance else { continue }
                items.append(Item(shape: s.id, path: i, poly: poly, box: Rect2(points: poly), length: len))
            }
        }
        var redundant = Set<Int>()
        var out: [VectorIssue] = []
        let order = items.indices.sorted { items[$0].box.min.x < items[$1].box.min.x }
        for (oi, a) in order.enumerated() {
            for b in order[(oi + 1)...] {
                if items[b].box.min.x > items[a].box.max.x + tolerance { break }
                guard items[a].box.insetBy(-tolerance).intersects(items[b].box) else { continue }
                // The shorter one (later one when equal) is the redundant copy.
                let (small, big) = items[a].length < items[b].length - tolerance ? (a, b)
                    : items[b].length < items[a].length - tolerance ? (b, a) : (max(a, b), min(a, b))
                guard !redundant.contains(small), !redundant.contains(big) else { continue }
                if covers(items[big].poly, items[small].poly, tolerance: tolerance) {
                    redundant.insert(small)
                    out.append(VectorIssue(kind: .duplicate, shapeID: items[small].shape, pathIndex: items[small].path,
                                           location: items[small].poly[0], otherShapeID: items[big].shape))
                }
            }
        }
        return out.sorted { ($0.shapeID.uuidString, $0.pathIndex ?? -1) < ($1.shapeID.uuidString, $1.pathIndex ?? -1) }
    }

    /// Applies the automatic repair for every fixable issue. Shapes left with no paths are
    /// dropped. Returns the repaired shapes (unchanged ones included, same order).
    public static func fix(_ shapes: [Shape], issues: [VectorIssue], tolerance: Double) -> [Shape] {
        var byShape: [UUID: [VectorIssue]] = [:]
        for i in issues where i.kind.isFixable { byShape[i.shapeID, default: []].append(i) }
        return shapes.compactMap { s in
            guard let list = byShape[s.id] else { return s }
            if list.contains(where: { $0.kind == .zeroLength && $0.pathIndex == nil }) { return nil }
            var remove = Set<Int>()
            var paths = s.paths
            for issue in list {
                guard let i = issue.pathIndex, paths.indices.contains(i) else { continue }
                switch issue.kind {
                case .zeroLength, .duplicate: remove.insert(i)
                case .zeroLengthSegments: paths[i] = removingZeroSegments(paths[i], tolerance: tolerance)
                case .nearlyClosed: paths[i] = closing(paths[i])
                case .selfIntersecting: break
                case .open: break
                }
            }
            // Self-intersections last (after closing) so the result is a clean outline.
            var extra: [Path] = []
            for issue in list where issue.kind == .selfIntersecting {
                guard let i = issue.pathIndex, paths.indices.contains(i), !remove.contains(i), paths[i].isClosed else { continue }
                let parts = PathOps.union([paths[i]], tolerance: max(tolerance / 4, 1e-6))
                guard let first = parts.first else { continue }
                paths[i] = first
                extra += parts.dropFirst()
            }
            var c = s
            c.paths = paths.enumerated().filter { !remove.contains($0.offset) }.map(\.element) + extra
            if c.paths != s.paths { c.origin = .derived(operation: "repair") }
            return c.paths.isEmpty ? nil : c
        }
    }

    // MARK: - Helpers

    static func zeroSegmentIndices(_ p: Path, tolerance: Double) -> [Int] {
        p.segments.indices.filter { k in
            let a = p.startOfSegment(k)
            switch p.segments[k] {
            case .line(let to): return a.distance(to: to) <= tolerance
            case .arc: return false  // start == end is a full circle
            case .cubic(let to, let c1, let c2):
                return [to, c1, c2].allSatisfy { $0.distance(to: a) <= tolerance }
            }
        }
    }

    static func removingZeroSegments(_ p: Path, tolerance: Double) -> Path {
        let drop = Set(zeroSegmentIndices(p, tolerance: tolerance))
        guard !drop.isEmpty else { return p }
        var out = Path(start: p.start, isClosed: p.isClosed)
        for (k, s) in p.segments.enumerated() where !drop.contains(k) { out.segments.append(s) }
        // A dropped first segment leaves a tiny jump at the start: absorb it.
        if let first = p.segments.indices.first, drop.contains(first) { out.start = p.segments[first].end }
        return out
    }

    static func closing(_ p: Path) -> Path {
        var c = p
        if case .line = c.segments.last, c.segments.count > 2 { c.segments[c.segments.count - 1] = .line(to: c.start) }
        c.isClosed = true
        return c
    }

    /// True when every point of `small` (sampled along it) lies within `tolerance` of `big`.
    static func covers(_ big: [Vec2], _ small: [Vec2], tolerance: Double) -> Bool {
        let box = Rect2(points: big).insetBy(-tolerance)
        let smallBox = Rect2(points: small)
        guard box.contains(smallBox.min), box.contains(smallBox.max) else { return false }
        var samples: [Vec2] = []
        for (a, b) in zip(small, small.dropFirst()) {
            let n = max(1, min(8, Int(a.distance(to: b) / max(tolerance * 50, 1e-9))))
            for k in 0..<n { samples.append(a.lerp(to: b, Double(k) / Double(n))) }
        }
        samples.append(small.last!)
        return samples.allSatisfy { distance($0, toPolyline: big) <= tolerance }
    }

    static func distance(_ p: Vec2, toPolyline poly: [Vec2]) -> Double {
        var best = Double.infinity
        for (a, b) in zip(poly, poly.dropFirst()) { best = min(best, segmentDistance(p, a, b)) }
        return best
    }

    static func segmentDistance(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
        let ab = b - a
        let l2 = ab.lengthSquared
        guard l2 > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        return p.distance(to: a + ab * t)
    }

    /// First proper crossing of a polyline with itself (adjacent segments ignored).
    static func selfIntersection(_ pts: [Vec2], closed: Bool, tolerance: Double) -> Vec2? {
        var poly = pts
        if closed, let f = poly.first { poly.append(f) }
        let n = poly.count - 1
        guard n >= 3 else { return nil }
        struct Seg { var i: Int; var a: Vec2; var b: Vec2; var minX: Double; var maxX: Double }
        let segs = (0..<n).map { i in
            Seg(i: i, a: poly[i], b: poly[i + 1], minX: min(poly[i].x, poly[i + 1].x), maxX: max(poly[i].x, poly[i + 1].x))
        }.sorted { $0.minX < $1.minX }
        for (k, s) in segs.enumerated() {
            for t in segs[(k + 1)...] {
                if t.minX > s.maxX { break }
                let d = abs(s.i - t.i)
                if d <= 1 || (closed && d == n - 1) { continue }
                if let x = properIntersection(s.a, s.b, t.a, t.b, tolerance: tolerance) { return x }
            }
        }
        return nil
    }

    /// Intersection strictly inside both segments (touching ends within `tolerance` ignored).
    static func properIntersection(_ p1: Vec2, _ p2: Vec2, _ q1: Vec2, _ q2: Vec2, tolerance: Double) -> Vec2? {
        let r = p2 - p1, s = q2 - q1
        let den = r.cross(s)
        guard abs(den) > 1e-15 else { return nil }
        let t = (q1 - p1).cross(s) / den, u = (q1 - p1).cross(r) / den
        let et = tolerance / max(r.length, 1e-12), eu = tolerance / max(s.length, 1e-12)
        guard t > et, t < 1 - et, u > eu, u < 1 - eu else { return nil }
        return p1 + r * t
    }
}
