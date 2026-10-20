import Foundation

/// Settings for true-shape nesting. All lengths in document units.
public struct NestSettings: Hashable, Sendable {
    public var sheetWidth: Double
    public var sheetHeight: Double
    /// Clearance between parts and the sheet edges.
    public var margin: Double
    /// Minimum gap between parts (typically a little more than the cutter diameter).
    public var spacing: Double
    /// Rotation increment in degrees; 0 keeps every part's orientation (90 = 0/90/180/270).
    public var rotationStep: Double
    /// Allow small parts to be placed inside holes of larger ones.
    public var nestInHoles: Bool
    /// Upper limit on sheets; parts that do not fit on these are reported as unplaced.
    public var maxSheets: Int
    /// Cell size of the occupancy grid; nil picks one from the sheet size and `precision`.
    public var cellSize: Double?
    /// Approximate number of grid cells per sheet when `cellSize` is nil.
    public var precision: Int

    public init(sheetWidth: Double, sheetHeight: Double, margin: Double = 0.25, spacing: Double = 0.375,
                rotationStep: Double = 90, nestInHoles: Bool = true, maxSheets: Int = 1,
                cellSize: Double? = nil, precision: Int = 1_000_000) {
        self.sheetWidth = sheetWidth; self.sheetHeight = sheetHeight; self.margin = margin
        self.spacing = spacing; self.rotationStep = rotationStep; self.nestInHoles = nestInHoles
        self.maxSheets = maxSheets; self.cellSize = cellSize; self.precision = precision
    }

    /// Grid cell size actually used.
    public var resolvedCellSize: Double {
        if let c = cellSize, c > 0 { return c }
        let area = max(sheetWidth * sheetHeight, 1e-9)
        return max((area / Double(max(precision, 1000))).squareRoot(), max(sheetWidth, sheetHeight) / 8000)
    }

    /// Rotations tried for every part, in degrees.
    public var rotations: [Double] {
        guard rotationStep > 0.01, rotationStep < 360 else { return [0] }
        return Array(stride(from: 0.0, to: 359.999, by: rotationStep))
    }
}

/// One distinct part: its outline (closed polygons, even-odd, in the design's coordinates)
/// and how many copies to place.
public struct NestPart: Hashable, Sendable {
    public var outline: [[Vec2]]
    public var quantity: Int

    public init(outline: [[Vec2]], quantity: Int = 1) {
        self.outline = outline; self.quantity = quantity
    }

    /// Area of the outline (holes subtracted, even-odd).
    public var area: Double {
        let depths = Self.depths(outline)
        return zip(outline, depths).reduce(0) { $0 + abs(PathGeometry.area($1.0)) * ($1.1.isMultiple(of: 2) ? 1 : -1) }
    }

    /// Nesting depth of each loop (0 = outer).
    static func depths(_ loops: [[Vec2]]) -> [Int] {
        loops.indices.map { i in
            guard let probe = loops[i].first else { return 0 }
            return loops.indices.filter { $0 != i && loops[$0].count > 2 && PathGeometry.contains(loops[$0], probe) }.count
        }
    }
}

/// Where one copy of a part goes.
public struct NestPlacement: Hashable, Sendable {
    public var part: Int
    /// 0-based copy number of the part.
    public var copy: Int
    /// 0-based sheet index.
    public var sheet: Int
    /// Rotation applied, degrees counter-clockwise.
    public var rotation: Double
    /// Maps the part from design coordinates to the sheet frame (lower-left = 0,0).
    public var transform: Transform2D
}

public struct NestResult: Sendable {
    public var placements: [NestPlacement]
    /// Copies that did not fit, per part index.
    public var unplaced: [Int: Int]
    /// Sheets with at least one part.
    public var sheetsUsed: Int
    /// Part area / usable sheet area, per used sheet.
    public var utilisation: [Double]

    public var unplacedCount: Int { unplaced.values.reduce(0, +) }
}

/// True-shape nesting: parts are rasterised (dilated by half the spacing plus half a cell
/// diagonal, so any two parts whose cells do not overlap are at least `spacing` apart) and
/// placed largest first at the lowest, then leftmost, free position over all allowed
/// rotations. Sheets are filled in order; a new sheet opens when a part fits on none.
public enum Nester {
    public static func nest(_ parts: [NestPart], settings s: NestSettings, obstacles: [[Vec2]] = [],
                            firstSheetObstacles: [[Vec2]] = []) -> NestResult {
        let cell = s.resolvedCellSize
        let dilation = max(0, s.spacing) / 2 + cell * 0.7072
        let pad = Int((dilation / cell).rounded(.up)) + 2
        let gridOrigin = Vec2(-Double(pad) * cell, -Double(pad) * cell)
        let cols = Int((s.sheetWidth / cell).rounded(.up)) + 2 * pad
        let rows = Int((s.sheetHeight / cell).rounded(.up)) + 2 * pad
        let usable = max(1e-9, (s.sheetWidth - 2 * s.margin) * (s.sheetHeight - 2 * s.margin))

        func dilate(_ polys: [[Vec2]]) -> [[Vec2]] {
            GeomKernel.offset(polys, by: dilation, join: .round, arcTolerance: cell / 8)
        }
        let blocked = NestRaster.make(dilate(obstacles), cell: cell, origin: gridOrigin)
        let blockedFirst = NestRaster.make(dilate(firstSheetObstacles), cell: cell, origin: gridOrigin)

        // Prepared rotations per part.
        struct Variant {
            var rotation: Double
            var raster: NestRaster
            var kx: Int, ky: Int
            var bounds: Rect2
        }
        let variants: [[Variant]] = parts.map { part in
            let clean = GeomKernel.boolean(.union, subject: part.outline.filter { $0.count > 2 }, clip: [],
                                           fillRule: .evenOdd)
            var loops = clean
            if !s.nestInHoles {
                let d = NestPart.depths(clean)
                loops = zip(clean, d).filter { $0.1 == 0 }.map(\.0)
            }
            return s.rotations.compactMap { deg -> Variant? in
                let t = Transform2D.rotation(deg * .pi / 180)
                let rotated = loops.map { $0.map(t.apply) }
                let b = Rect2(points: rotated.joined())
                guard !b.isEmpty else { return nil }
                let grown = dilate(rotated)
                let gb = Rect2(points: grown.joined())
                let kx = Int(((gb.min.x - gridOrigin.x) / cell).rounded(.down))
                let ky = Int(((gb.min.y - gridOrigin.y) / cell).rounded(.down))
                let local = gridOrigin + Vec2(Double(kx) * cell, Double(ky) * cell)
                let r = NestRaster.make(grown, cell: cell, origin: local)
                return Variant(rotation: deg, raster: r, kx: kx, ky: ky, bounds: b)
            }
        }

        // Copies, largest first (stable for equal areas).
        var queue: [(part: Int, copy: Int, area: Double)] = []
        for (i, p) in parts.enumerated() where p.quantity > 0 {
            let a = p.area
            for c in 0..<p.quantity { queue.append((i, c, a)) }
        }
        queue = queue.enumerated().sorted { ($0.element.area, -$0.offset) > ($1.element.area, -$1.offset) }.map(\.element)

        var sheets: [NestGrid] = []
        var sheetArea: [Double] = []
        func newSheet() -> NestGrid {
            var g = NestGrid(cols: cols, rows: rows)
            g.mark(blocked, dx: 0, dy: 0)
            if sheets.isEmpty { g.mark(blockedFirst, dx: 0, dy: 0) }
            return g
        }

        /// Lowest-then-leftmost fit of a variant on a grid: (dx, dy) cell shift and placed top.
        func bestFit(_ v: Variant, on g: NestGrid) -> (dx: Int, dy: Int, top: Double, left: Double)? {
            let xMin = Int(((s.margin - v.bounds.min.x) / cell - 1e-9).rounded(.up))
            let xMax = Int(((s.sheetWidth - s.margin - v.bounds.max.x) / cell + 1e-9).rounded(.down))
            let yMin = Int(((s.margin - v.bounds.min.y) / cell - 1e-9).rounded(.up))
            let yMax = Int(((s.sheetHeight - s.margin - v.bounds.max.y) / cell + 1e-9).rounded(.down))
            guard xMin <= xMax, yMin <= yMax, !v.raster.isEmpty else { return nil }
            // Shift (in cells) so the variant's local cell (0,0) lands on grid cell (kx + shift).
            for sy in yMin...yMax {
                var sx = xMin
                while sx <= xMax {
                    let skip = g.blockedSkip(v.raster, dx: v.kx + sx, dy: v.ky + sy)
                    if skip == 0 {
                        return (v.kx + sx, v.ky + sy, v.bounds.max.y + Double(sy) * cell, v.bounds.min.x + Double(sx) * cell)
                    }
                    sx += skip
                }
            }
            return nil
        }

        func fitsEmptySheet(_ v: Variant) -> Bool {
            v.bounds.width <= s.sheetWidth - 2 * s.margin + 1e-9 && v.bounds.height <= s.sheetHeight - 2 * s.margin + 1e-9
        }

        var placements: [NestPlacement] = []
        var unplaced: [Int: Int] = [:]
        for item in queue {
            let vs = variants[item.part]
            var placed = false
            var sheetIndex = 0
            // A part larger than an empty sheet never opens new sheets.
            while vs.contains(where: fitsEmptySheet) {
                var fresh = false
                if sheetIndex == sheets.count {
                    guard sheets.count < max(1, s.maxSheets) else { break }
                    sheets.append(newSheet())
                    sheetArea.append(0)
                    fresh = true
                }
                var best: (v: Variant, dx: Int, dy: Int, top: Double, left: Double)?
                for v in vs {
                    guard let f = bestFit(v, on: sheets[sheetIndex]) else { continue }
                    if best == nil || (f.top, f.left) < (best!.top - 1e-9, best!.left) {
                        best = (v, f.dx, f.dy, f.top, f.left)
                    }
                }
                if let b = best {
                    sheets[sheetIndex].mark(b.v.raster, dx: b.dx, dy: b.dy)
                    let shift = Vec2(Double(b.dx - b.v.kx) * cell, Double(b.dy - b.v.ky) * cell)
                    let t = Transform2D.rotation(b.v.rotation * .pi / 180).concatenating(.translation(shift))
                    placements.append(NestPlacement(part: item.part, copy: item.copy, sheet: sheetIndex,
                                                    rotation: b.v.rotation, transform: t))
                    sheetArea[sheetIndex] += item.area
                    placed = true
                    break
                }
                if fresh && sheetIndex > 0 {
                    // Does not fit on an empty sheet (obstacles): more sheets will not help.
                    sheets.removeLast()
                    sheetArea.removeLast()
                    break
                }
                sheetIndex += 1
            }
            if !placed { unplaced[item.part, default: 0] += 1 }
        }
        let used = Set(placements.map(\.sheet)).count
        return NestResult(placements: placements.sorted { ($0.part, $0.copy) < ($1.part, $1.copy) },
                          unplaced: unplaced, sheetsUsed: used,
                          utilisation: sheetArea.prefix(used).map { $0 / usable })
    }
}
