import CADCore
import Foundation

public extension ReliefHeightmap {
    /// Flat-cutter drop depths at every cell centre: cell (i, j) of the result holds the deepest a
    /// flat cutter of `radius` centred on `position(i, j)` can go without dipping below any cell
    /// square it overlaps. Same rule as `DropCutter` with a `.flat` profile, but computed for the
    /// whole grid at once (row-wise sliding minima, one pass per distinct row half-width).
    func eroded(radius: Double) -> ReliefHeightmap {
        var out = ReliefHeightmap(origin: origin, cellSize: cellSize, columns: columns, rows: rows,
                                  baseDepth: baseDepth)
        guard columns > 0, rows > 0 else { return out }
        let cs = cellSize, half = cs / 2, r = max(0, radius)
        // Half-width (in cells) of the window for each row offset dj.
        var widths: [Int: [Int]] = [:]
        let maxDj = min(rows - 1, Int(floor((r + half) / cs)))
        for dj in 0...max(0, maxDj) {
            let dy = max(0, Double(dj) * cs - half)
            guard dy <= r + 1e-12 else { continue }
            let w = min(columns - 1, Int(floor(((r * r - dy * dy).squareRoot() + half) / cs + 1e-9)))
            widths[w, default: []].append(dj)
        }
        var result = [Double](repeating: .infinity, count: columns * rows)
        var rowMin = [Double](repeating: 0, count: columns * rows)
        for (w, djs) in widths {
            for j in 0..<rows {
                Self.slidingMin(depths, from: j * columns, count: columns, halfWidth: w, into: &rowMin)
            }
            for j in 0..<rows {
                for dj in djs {
                    for jj in dj == 0 ? [j] : [j - dj, j + dj] where jj >= 0 && jj < rows {
                        let a = j * columns, b = jj * columns
                        for i in 0..<columns where rowMin[b + i] < result[a + i] { result[a + i] = rowMin[b + i] }
                    }
                }
            }
        }
        out.depths = result
        return out
    }

    /// `out[start + i] = min(a[start + max(0, i - w) ... start + min(n - 1, i + w)])` (monotone deque).
    private static func slidingMin(_ a: [Double], from start: Int, count n: Int, halfWidth w: Int,
                                   into out: inout [Double]) {
        var deque = [Int](repeating: 0, count: n)
        var head = 0, tail = 0
        var next = 0 // next index to push
        for i in 0..<n {
            let hi = min(n - 1, i + w)
            while next <= hi {
                let v = a[start + next]
                while tail > head, a[start + deque[tail - 1]] >= v { tail -= 1 }
                deque[tail] = next; tail += 1
                next += 1
            }
            while deque[head] < i - w { head += 1 }
            out[start + i] = a[start + deque[head]]
        }
    }
}

/// Iso-contours of a scalar grid (marching squares).
enum MarchingSquares {
    /// Closed loops bounding the cells whose value is `>= threshold` (outside the grid counts as
    /// below). Saddle cells are always split (the two inside corners are kept apart), so the
    /// result never joins regions through a saddle. Loops are unoriented; normalise them with an
    /// even-odd union.
    static func loops(_ grid: ReliefHeightmap, threshold: Double) -> [[Vec2]] {
        let cols = grid.columns, rows = grid.rows
        guard cols > 0, rows > 0 else { return [] }
        let eps = 1e-9
        func inside(_ i: Int, _ j: Int) -> Bool {
            i >= 0 && j >= 0 && i < cols && j < rows && grid.depths[j * cols + i] >= threshold - eps
        }
        let stride = cols + 2
        // Edge keys: horizontal edge (i,j)-(i+1,j) and vertical edge (i,j)-(i,j+1), i/j from -1.
        func hKey(_ i: Int, _ j: Int) -> Int { ((j + 1) * stride + (i + 1)) * 2 }
        func vKey(_ i: Int, _ j: Int) -> Int { ((j + 1) * stride + (i + 1)) * 2 + 1 }
        func value(_ i: Int, _ j: Int) -> Double? {
            i >= 0 && j >= 0 && i < cols && j < rows ? grid.depths[j * cols + i] : nil
        }
        func crossing(_ ai: Int, _ aj: Int, _ bi: Int, _ bj: Int) -> Vec2 {
            let pa = grid.position(ai, aj), pb = grid.position(bi, bj)
            guard let fa = value(ai, aj), let fb = value(bi, bj), abs(fb - fa) > 1e-15 else {
                return pa.lerp(to: pb, 0.5)
            }
            let t = min(max((threshold - fa) / (fb - fa), 0), 1)
            return pa.lerp(to: pb, t)
        }
        var points: [Int: Vec2] = [:]
        var links: [Int: [Int]] = [:]
        func addSegment(_ a: Int, _ b: Int) {
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        for j in -1..<rows {
            for i in -1..<cols {
                let b0 = inside(i, j), b1 = inside(i + 1, j), b2 = inside(i + 1, j + 1), b3 = inside(i, j + 1)
                let idx = (b0 ? 1 : 0) | (b1 ? 2 : 0) | (b2 ? 4 : 0) | (b3 ? 8 : 0)
                if idx == 0 || idx == 15 { continue }
                let bottom = hKey(i, j), top = hKey(i, j + 1), left = vKey(i, j), right = vKey(i + 1, j)
                func point(_ k: Int) {
                    guard points[k] == nil else { return }
                    switch k {
                    case bottom: points[k] = crossing(i, j, i + 1, j)
                    case top: points[k] = crossing(i, j + 1, i + 1, j + 1)
                    case left: points[k] = crossing(i, j, i, j + 1)
                    default: points[k] = crossing(i + 1, j, i + 1, j + 1)
                    }
                }
                let segs: [(Int, Int)]
                switch idx {
                case 1, 14: segs = [(left, bottom)]
                case 2, 13: segs = [(bottom, right)]
                case 3, 12: segs = [(left, right)]
                case 4, 11: segs = [(right, top)]
                case 6, 9: segs = [(bottom, top)]
                case 7, 8: segs = [(left, top)]
                case 5: segs = [(left, bottom), (right, top)]
                default: segs = [(bottom, right), (top, left)] // 10
                }
                for (a, b) in segs { point(a); point(b); addSegment(a, b) }
            }
        }
        var visited = Set<Int>()
        var out: [[Vec2]] = []
        // Sorted so the output is deterministic (dictionary order is not).
        for start in links.keys.sorted() where !visited.contains(start) {
            var loop: [Vec2] = []
            var prev = -1, cur = start
            while !visited.contains(cur) {
                visited.insert(cur)
                loop.append(points[cur]!)
                let nbrs = links[cur] ?? []
                guard let nxt = nbrs.first(where: { $0 != prev && !visited.contains($0) })
                        ?? nbrs.first(where: { $0 != prev }) else { break }
                prev = cur; cur = nxt
            }
            if loop.count >= 3 { out.append(loop) }
        }
        return out
    }
}

/// Tool-centre regions for Z-level roughing: where a flat cutter (grown by the allowance) can
/// sit at a given depth without touching the model.
struct ReliefLevelRegions {
    /// Deepest tool-tip depth at each grid point (the flat-cutter drop depth minus the allowance).
    let floors: ReliefHeightmap
    /// Machining boundary for the tool centre (even-odd normalised).
    let boundary: [[Vec2]]
    let tolerance: Double

    /// - Parameters:
    ///   - toolRadius: flat end mill radius.
    ///   - allowance: stock left on the model sideways and vertically.
    ///   - boundary: closed loops limiting the tool centre.
    init(map: ReliefHeightmap, toolRadius: Double, allowance: Double, boundary: [[Vec2]], tolerance: Double) {
        let a = max(0, allowance)
        // Grow the cutter by 1.5 cells: every point of a contour region lies within that distance
        // of an allowed grid point, so the contours are safe between samples too.
        var f = map.eroded(radius: toolRadius + a + 1.5 * map.cellSize)
        for k in f.depths.indices { f.depths[k] -= a }
        floors = f
        self.boundary = Polygon2D.region(fromLoops: boundary)
        self.tolerance = tolerance
    }

    /// Deepest floor of any grid point inside the boundary (0 when none).
    var deepestFloor: Double {
        let bounds = Rect2(points: boundary.flatMap { $0 })
        var deepest = 0.0
        for j in 0..<floors.rows {
            for i in 0..<floors.columns {
                let d = floors[i, j]
                guard d > deepest else { continue }
                let p = floors.position(i, j)
                if bounds.contains(p), Polygon2D.regionContains(boundary, p) { deepest = d }
            }
        }
        return deepest
    }

    /// Tool-centre region (even-odd normalised, outer loops CCW) at `level`, clipped to the
    /// boundary. Contours are simplified within `tolerance / 2` and then shrunk by that much, so
    /// they stay on the safe side.
    func region(at level: Double) -> [[Vec2]] {
        let raw = MarchingSquares.loops(floors, threshold: level)
        guard !raw.isEmpty else { return [] }
        let tol = max(tolerance, 1e-9)
        let simplified = raw.map { loop -> [Vec2] in
            let closed = (loop + [loop[0]]).map { Vec3($0, z: 0) }
            return Polyline3D.simplify(closed, tolerance: tol / 2).dropLast().map(\.xy)
        }.filter { $0.count >= 3 }
        let normalised = Polygon2D.region(fromLoops: simplified)
        let shrunk = GeomKernel.offset(normalised, by: -tol / 2, join: .round, arcTolerance: tol)
        let clipped = GeomKernel.boolean(.intersection, subject: shrunk, clip: boundary, fillRule: .evenOdd)
        return clipped.map { Polygon2D.deduplicated($0, closed: true, tolerance: tol * 1e-3) }
            .filter { $0.count > 2 && abs(Polygon2D.signedArea($0)) > tol * tol }
    }
}
