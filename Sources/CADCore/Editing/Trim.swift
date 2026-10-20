import Foundation

/// Trimming vectors at their intersections with other vectors.
public enum Trim {
    /// Removes the span of `path` around `click` that lies between its neighbouring
    /// intersections with `cutters` (and itself). Returns the remaining pieces (empty = the whole
    /// path goes, when nothing crosses it).
    public static func trimSpan(_ path: Path, cutters: [Path], at click: Vec2, tolerance: Double) -> [Path] {
        let flat = max(tolerance / 4, 1e-6)
        let a = PathSplitting.sample(path, tolerance: flat)
        var cuts: [Double] = []
        for c in cutters { cuts += PathSplitting.intersections(a, PathSplitting.sample(c, tolerance: flat), tolerance: tolerance) }
        cuts += PathSplitting.selfIntersections(a)
        let total = Double(PathSplitting.closedSegments(path).count)
        // Ignore hits at the very ends of open paths (touching, not crossing).
        cuts = PathSplitting.dedupe(cuts.sorted(), tolerance: 1e-6).filter { path.isClosed || ($0 > 1e-6 && $0 < total - 1e-6) }
        if path.isClosed { cuts = cuts.map { $0 >= total - 1e-9 ? 0 : $0 } ; cuts = PathSplitting.dedupe(cuts.sorted(), tolerance: 1e-6) }
        guard !cuts.isEmpty else { return [] }
        let s = PathSplitting.nearestParameter(a, to: click).param
        if path.isClosed {
            guard cuts.count >= 2 else { return [] }
            // Span (lo, hi) containing s, possibly wrapping through the start.
            let lo = cuts.last { $0 <= s } ?? cuts.last!
            let hi = cuts.first { $0 > s } ?? cuts.first!
            return [PathSplitting.subpath(path, from: hi, to: lo)]
        }
        let lo = cuts.last { $0 <= s }, hi = cuts.first { $0 > s }
        var out: [Path] = []
        if let lo { out.append(PathSplitting.subpath(path, from: 0, to: lo)) }
        if let hi { out.append(PathSplitting.subpath(path, from: hi, to: total)) }
        return out
    }

    /// Splits `path` at every crossing with `boundary` and keeps the pieces inside (or outside)
    /// the closed `boundary`. A path that does not cross is kept or dropped whole.
    public static func toBoundary(_ path: Path, boundary: [Path], keepInside: Bool, tolerance: Double) -> [Path] {
        let flat = max(tolerance / 4, 1e-6)
        let regions = boundary.filter(\.isClosed).map { $0.flattened(tolerance: flat) }
        guard !regions.isEmpty else { return [path] }
        func inside(_ p: Vec2) -> Bool {
            regions.reduce(false) { $0 != PathGeometry.contains($1, p) }
        }
        let a = PathSplitting.sample(path, tolerance: flat)
        var cuts: [Double] = []
        for b in boundary where b.isClosed {
            cuts += PathSplitting.intersections(a, PathSplitting.sample(b, tolerance: flat), tolerance: tolerance)
        }
        let total = Double(PathSplitting.closedSegments(path).count)
        cuts = PathSplitting.dedupe(cuts.sorted(), tolerance: 1e-6).filter { $0 > 1e-9 && $0 < total - 1e-9 }
        if cuts.isEmpty {
            let probe = PathSplitting.point(path, at: total / 2)
            return inside(probe) == keepInside ? [path] : []
        }
        var bounds = cuts
        var pieces: [(Double, Double)] = []
        if path.isClosed {
            for i in bounds.indices { pieces.append((bounds[i], bounds[(i + 1) % bounds.count])) }
        } else {
            bounds = [0] + bounds + [total]
            for i in 0..<(bounds.count - 1) { pieces.append((bounds[i], bounds[i + 1])) }
        }
        return pieces.compactMap { lo, hi in
            var mid = lo < hi ? (lo + hi) / 2 : (lo + hi + total) / 2
            if mid >= total { mid -= total }
            guard inside(PathSplitting.point(path, at: mid)) == keepInside else { return nil }
            let p = PathSplitting.subpath(path, from: lo, to: hi)
            return p.segments.isEmpty ? nil : p
        }
    }
}
