import Foundation

/// Shape-level geometry operations (boolean, offset, join). Booleans/offsets return
/// polyline paths (arcs are flattened with `tolerance`).
public enum PathOps {
    // Each `[Path]` argument below is ONE shape's loops, read with the even-odd rule (the rule
    // the CAM side uses): a loop inside another is a hole whatever its direction. Loops are
    // normalised with an even-odd union before the operation runs.

    /// Union of closed paths, each path a separate filled region (non-zero fill). Use
    /// `union(shapes:)` to keep the holes of compound shapes.
    public static func union(_ paths: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        let polys = closedPolygons(paths, tolerance)
        return wrap(GeomKernel.boolean(.union, subject: polys, clip: []))
    }

    /// Union of several shapes; each shape's loops are read even-odd, so holes survive.
    public static func union(shapes: [[Path]], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.union, subject: shapes.flatMap { regions($0, tolerance) }, clip: []))
    }

    /// Union of `a` with `b` (each one shape, even-odd).
    public static func union(_ a: [Path], _ b: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.union, subject: regions(a, tolerance), clip: regions(b, tolerance)))
    }

    public static func subtract(_ a: [Path], minus b: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.difference, subject: regions(a, tolerance), clip: regions(b, tolerance)))
    }

    public static func intersect(_ a: [Path], with b: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.intersection, subject: regions(a, tolerance), clip: regions(b, tolerance)))
    }

    public static func xor(_ a: [Path], _ b: [Path], tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.boolean(.xor, subject: regions(a, tolerance), clip: regions(b, tolerance)))
    }

    /// Offset closed paths outward (positive) or inward (negative).
    public static func offset(_ paths: [Path], by distance: Double, join: GeomKernel.Join = .round,
                              tolerance: Double = Path.defaultTolerance) -> [Path] {
        wrap(GeomKernel.offset(regions(paths, tolerance), by: distance, join: join,
                               arcTolerance: tolerance))
    }

    /// Closed outline around open paths at `distance` on both sides.
    public static func offsetOpen(_ paths: [Path], by distance: Double, join: GeomKernel.Join = .round,
                                  end: GeomKernel.EndType = .openRound,
                                  tolerance: Double = Path.defaultTolerance) -> [Path] {
        let polys = paths.filter { !$0.isClosed }.map { $0.flattened(tolerance: tolerance) }.filter { $0.count > 1 }
        return wrap(GeomKernel.offset(polys, by: abs(distance), join: join, end: end, arcTolerance: tolerance))
    }

    /// Join open paths whose endpoints are within `tolerance`, closing loops when possible.
    /// Paths are reversed as needed and joints are snapped together; closed inputs pass through
    /// unchanged. A chain whose ends meet within `tolerance` is closed.
    /// Output: closed inputs first, then chains in the order of their first member.
    public static func joinOpenPaths(_ paths: [Path], tolerance: Double) -> [Path] {
        joinOpenPathsReporting(paths, tolerance: tolerance).paths
    }

    /// The joined paths, and the largest gap that joining closed by moving ends together.
    public struct JoinResult: Equatable, Sendable {
        public var paths: [Path]
        /// Zero when every joined pair of ends already touched (or nothing joined).
        public var largestGapClosed: Double
    }

    /// `joinOpenPaths`, also reporting how far the ends moved: the largest distance between two
    /// ends that were snapped together, counting the gap that closes a loop.
    public static func joinOpenPathsReporting(_ paths: [Path], tolerance: Double) -> JoinResult {
        var result = paths.filter(\.isClosed)
        let open = paths.filter { !$0.isClosed && !$0.isEmpty }
        var used = [Bool](repeating: false, count: open.count)
        let tol = max(tolerance, 0)
        var largestGap = 0.0

        for i in open.indices where !used[i] {
            used[i] = true
            var chain = open[i]
            while !isLoop(chain, tol) {
                if let (j, endMatched, gap) = bestMatch(for: chain.end, in: open, used: used, tolerance: tol) {
                    used[j] = true
                    largestGap = max(largestGap, gap)
                    append(endMatched ? open[j].reversed() : open[j], to: &chain)
                } else if let (j, endMatched, gap) = bestMatch(for: chain.start, in: open, used: used, tolerance: tol) {
                    used[j] = true
                    largestGap = max(largestGap, gap)
                    var front = endMatched ? open[j] : open[j].reversed()
                    append(chain, to: &front)
                    chain = front
                } else {
                    break
                }
            }
            if isLoop(chain, tol) {
                largestGap = max(largestGap, chain.end.distance(to: chain.start))
                result.append(closing(chain))
            } else {
                result.append(chain)
            }
        }
        return JoinResult(paths: result, largestGapClosed: largestGap)
    }

    /// How many open vectors have ends that nearly meet, and how far apart those ends are.
    public struct EndGapReport: Equatable, Sendable {
        public var vectorCount: Int
        public var smallestGap: Double
        public var largestGap: Double
    }

    /// Finds open paths with an end that lies more than `tolerance` but no more than `limit` from
    /// another end: the signature of a gap in a drawing that `joinOpenPaths(tolerance:)` leaves
    /// open. A path's own two ends count, so an outline that stops short of closing is found.
    /// A grid lookup keeps this linear in the number of ends. Nil when there is no such pair.
    public static func nearlyMeetingEnds(_ paths: [Path], beyond tolerance: Double, upTo limit: Double) -> EndGapReport? {
        guard limit > 0, limit > tolerance else { return nil }
        var ends: [(point: Vec2, path: Int)] = []
        for (i, p) in paths.enumerated() where !p.isClosed && !p.isEmpty {
            ends.append((p.start, i))
            ends.append((p.end, i))
        }
        guard ends.count > 1 else { return nil }

        struct Cell: Hashable { var x: Int; var y: Int }
        func cell(_ v: Vec2) -> Cell { Cell(x: Int((v.x / limit).rounded(.down)), y: Int((v.y / limit).rounded(.down))) }
        var grid: [Cell: [Int]] = [:]
        for (i, e) in ends.enumerated() { grid[cell(e.point), default: []].append(i) }

        var involved = Set<Int>()
        var smallest = Double.infinity, largest = 0.0
        for (i, e) in ends.enumerated() {
            let c = cell(e.point)
            var nearest = Double.infinity
            for dx in -1...1 {
                for dy in -1...1 {
                    for j in grid[Cell(x: c.x + dx, y: c.y + dy)] ?? [] where j != i {
                        let d = e.point.distance(to: ends[j].point)
                        if d > tolerance && d <= limit { nearest = min(nearest, d) }
                    }
                }
            }
            guard nearest.isFinite else { continue }
            involved.insert(e.path)
            smallest = min(smallest, nearest)
            largest = max(largest, nearest)
        }
        guard !involved.isEmpty else { return nil }
        return EndGapReport(vectorCount: involved.count, smallestGap: smallest, largestGap: largest)
    }

    /// Returns `path` closed if its end is within `tolerance` of its start (the last point is
    /// snapped onto the start); otherwise unchanged.
    public static func closeIfNearlyClosed(_ path: Path, tolerance: Double) -> Path {
        guard !path.isClosed, isLoop(path, tolerance) else { return path }
        return closing(path)
    }

    /// Force-close an open path (an implicit closing line is added).
    public static func close(_ path: Path) -> Path {
        var p = path
        p.isClosed = true
        return p
    }

    // MARK: - Helpers

    /// One shape's closed loops as a clean region: even-odd union, so holes come out wound
    /// opposite to their outer loop and non-zero operations keep them.
    static func regions(_ paths: [Path], _ tol: Double) -> [[Vec2]] {
        let polys = closedPolygons(paths, tol)
        guard polys.count > 1 else { return polys }
        return GeomKernel.boolean(.union, subject: polys, clip: [], fillRule: .evenOdd)
    }

    static func closedPolygons(_ paths: [Path], _ tol: Double) -> [[Vec2]] {
        paths.filter(\.isClosed).map { $0.flattened(tolerance: tol) }
    }

    static func wrap(_ polys: [[Vec2]]) -> [Path] {
        polys.filter { $0.count > 2 }.map { Path(points: $0, closed: true) }
    }

    /// True when the open path's ends meet and it encloses something (not a lone line).
    private static func isLoop(_ p: Path, _ tol: Double) -> Bool {
        guard !p.isEmpty, p.end.distance(to: p.start) <= tol else { return false }
        let curved = p.segments.contains { if case .line = $0 { return false }; return true }
        return p.segments.count > 2 || curved
    }

    /// Snap the final point onto the start and mark closed.
    private static func closing(_ path: Path) -> Path {
        var p = path
        if let last = p.segments.indices.last {
            p.segments[last] = moved(p.segments[last], to: p.start)
        }
        p.isClosed = true
        return p
    }

    private static func moved(_ s: PathSegment, to e: Vec2) -> PathSegment {
        switch s {
        case .line: return .line(to: e)
        case .arc(_, let c, let cw): return .arc(to: e, center: c, clockwise: cw)
        case .cubic(let old, let c1, let c2): return .cubic(to: e, control1: c1, control2: c2 + (e - old))
        }
    }

    /// Append `next` (which starts near `chain.end`) to `chain`; the joint snaps to `chain.end`.
    private static func append(_ next: Path, to chain: inout Path) {
        guard var first = next.segments.first else { return }
        if case .cubic(let to, let c1, let c2) = first {
            first = .cubic(to: to, control1: c1 + (chain.end - next.start), control2: c2)
        }
        chain.segments.append(first)
        chain.segments.append(contentsOf: next.segments.dropFirst())
    }

    /// Nearest unused open path with an endpoint within tolerance of `p`.
    /// Returns (index, true if its END matched, the distance to that endpoint).
    private static func bestMatch(for p: Vec2, in open: [Path], used: [Bool], tolerance: Double) -> (Int, Bool, Double)? {
        var best: (Int, Bool, Double)?
        var bestD = Double.infinity
        for (j, q) in open.enumerated() where !used[j] {
            let ds = q.start.distance(to: p), de = q.end.distance(to: p)
            if ds <= tolerance, ds < bestD { best = (j, false, ds); bestD = ds }
            if de <= tolerance, de < bestD { best = (j, true, de); bestD = de }
        }
        return best
    }
}
