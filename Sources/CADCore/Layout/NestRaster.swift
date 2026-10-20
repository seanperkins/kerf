import Foundation

/// Row spans of a polygon set on a square cell grid: a cell belongs to the set when its centre
/// lies inside the polygons (even-odd). Used by the nester for true-shape occupancy.
struct NestRaster {
    /// Index of the first row in `rows`.
    var firstRow: Int
    /// Per row, sorted disjoint inclusive column ranges.
    var rows: [[(lo: Int, hi: Int)]]

    var isEmpty: Bool { rows.allSatisfy(\.isEmpty) }

    /// Rasterises `polys` on the grid whose cell (i, j) has its centre at
    /// `origin + ((i + 0.5) * cell, (j + 0.5) * cell)`.
    static func make(_ polys: [[Vec2]], cell: Double, origin: Vec2) -> NestRaster {
        var box = Rect2.empty
        for p in polys { for v in p { box.include(v) } }
        guard !box.isEmpty else { return NestRaster(firstRow: 0, rows: []) }
        let j0 = Int((((box.min.y - origin.y) / cell) - 0.5).rounded(.up))
        let j1 = Int((((box.max.y - origin.y) / cell) - 0.5).rounded(.down))
        guard j1 >= j0 else { return NestRaster(firstRow: 0, rows: []) }
        var rows: [[(lo: Int, hi: Int)]] = []
        rows.reserveCapacity(j1 - j0 + 1)
        var xs: [Double] = []
        for j in j0...j1 {
            let yc = origin.y + (Double(j) + 0.5) * cell
            xs.removeAll(keepingCapacity: true)
            for poly in polys where poly.count > 2 {
                var a = poly[poly.count - 1]
                for b in poly {
                    if (a.y <= yc) != (b.y <= yc) {
                        xs.append(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y))
                    }
                    a = b
                }
            }
            xs.sort()
            var spans: [(lo: Int, hi: Int)] = []
            var k = 0
            while k + 1 < xs.count {
                let lo = Int((((xs[k] - origin.x) / cell) - 0.5).rounded(.up))
                let hi = Int((((xs[k + 1] - origin.x) / cell) - 0.5).rounded(.down))
                if hi >= lo {
                    if let last = spans.last, lo <= last.hi + 1 {
                        spans[spans.count - 1].hi = max(last.hi, hi)
                    } else {
                        spans.append((lo, hi))
                    }
                }
                k += 2
            }
            rows.append(spans)
        }
        return NestRaster(firstRow: j0, rows: rows)
    }
}

/// Occupancy of one sheet. `run[row * cols + col]` = number of free cells from that cell to
/// the right, so a span fits at a position with a single lookup; `blockedRun` counts occupied
/// cells the same way so a scan can jump over whole occupied stretches.
struct NestGrid {
    let cols: Int
    let rows: Int
    private var occupied: [Bool]
    private var run: [Int32]
    private var blockedRun: [Int32]

    init(cols: Int, rows: Int) {
        self.cols = cols; self.rows = rows
        occupied = Array(repeating: false, count: cols * rows)
        run = Array(repeating: 0, count: cols * rows)
        blockedRun = Array(repeating: 0, count: cols * rows)
        for r in 0..<rows { recompute(row: r) }
    }

    private mutating func recompute(row r: Int) {
        var n: Int32 = 0, b: Int32 = 0
        let base = r * cols
        for c in stride(from: cols - 1, through: 0, by: -1) {
            if occupied[base + c] {
                n = 0; b += 1
            } else {
                n += 1; b = 0
            }
            run[base + c] = n
            blockedRun[base + c] = b
        }
    }

    /// Marks the raster (shifted by dx, dy cells) as occupied; cells off the grid are ignored.
    mutating func mark(_ r: NestRaster, dx: Int, dy: Int) {
        for (k, spans) in r.rows.enumerated() {
            let row = r.firstRow + k + dy
            guard row >= 0, row < rows, !spans.isEmpty else { continue }
            for s in spans {
                let lo = max(0, s.lo + dx), hi = min(cols - 1, s.hi + dx)
                guard lo <= hi else { continue }
                for c in lo...hi { occupied[row * cols + c] = true }
            }
            recompute(row: row)
        }
    }

    /// 0 when the raster fits at (dx, dy); otherwise how many columns the scan can skip.
    func blockedSkip(_ r: NestRaster, dx: Int, dy: Int) -> Int {
        for (k, spans) in r.rows.enumerated() {
            let row = r.firstRow + k + dy
            for s in spans {
                let lo = s.lo + dx, hi = s.hi + dx
                guard row >= 0, row < rows, lo >= 0, hi < cols else { return 1 }
                let free = Int(run[row * cols + lo])
                if free < hi - lo + 1 {
                    // Every shift that puts this span's start inside the free stretch or the
                    // occupied stretch after it fails too.
                    let after = lo + free
                    return free + (after < cols ? Int(blockedRun[row * cols + after]) : cols)
                }
            }
        }
        return 0
    }

    /// Fraction of occupied cells (for reporting).
    var occupiedCount: Int { occupied.reduce(0) { $0 + ($1 ? 1 : 0) } }
}
