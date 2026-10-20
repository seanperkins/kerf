import CADCore
import Foundation

/// Regular grid of model surface depths (below the material top, positive = deeper).
///
/// Cell (i, j) is the square of side `cellSize` centred on `position(i, j)` and stores the
/// SHALLOWEST model depth anywhere inside that square (not just at its centre), so a cutter
/// that clears every cell square it overlaps can never gouge the model — whatever the
/// resolution. Cells the model does not cover hold `baseDepth` (the model's bottom plane).
public struct ReliefHeightmap: Sendable {
    /// Material-frame position of the centre of cell (0, 0).
    public var origin: Vec2
    public var cellSize: Double
    public var columns: Int
    public var rows: Int
    public var baseDepth: Double
    /// Row-major depths, `columns * rows`.
    public var depths: [Double]

    /// Hard cap on grid size so a silly resolution cannot exhaust memory.
    public static let maxCells = 30_000_000

    public init(origin: Vec2, cellSize: Double, columns: Int, rows: Int, baseDepth: Double) {
        self.origin = origin; self.cellSize = cellSize; self.columns = columns; self.rows = rows
        self.baseDepth = baseDepth
        depths = Array(repeating: baseDepth, count: columns * rows)
    }

    public subscript(i: Int, j: Int) -> Double {
        get { depths[j * columns + i] }
        set { depths[j * columns + i] = newValue }
    }

    public func position(_ i: Int, _ j: Int) -> Vec2 {
        Vec2(origin.x + Double(i) * cellSize, origin.y + Double(j) * cellSize)
    }

    /// Shallowest model point (min depth).
    public var minDepth: Double { depths.min() ?? baseDepth }
    /// Deepest model point (max depth).
    public var maxDepth: Double { depths.max() ?? baseDepth }

    /// Rasterises `model` over `area` (material frame) at `cellSize`.
    public static func rasterize(_ model: PlacedModel, over area: Rect2, cellSize: Double) throws -> ReliefHeightmap {
        try rasterize([model], over: area, cellSize: cellSize)
    }

    /// Composite heightmap of several models: each cell keeps the shallowest point of any model
    /// (a union of the solids). Cells no model covers hold the deepest model bottom plane.
    public static func rasterize(_ models: [PlacedModel], over area: Rect2, cellSize: Double) throws -> ReliefHeightmap {
        guard cellSize > 0, cellSize.isFinite else { throw CAMError.invalidParameter("Heightmap resolution must be > 0") }
        guard !area.isEmpty, !models.isEmpty else { throw CAMError.noGeometry }
        let cols = Int(ceil(area.width / cellSize)) + 1
        let rows = Int(ceil(area.height / cellSize)) + 1
        guard cols * rows <= maxCells else {
            throw CAMError.invalidParameter("Heightmap resolution too fine (\(cols)x\(rows) cells)")
        }
        var map = ReliefHeightmap(origin: area.min, cellSize: cellSize, columns: cols, rows: rows,
                                  baseDepth: models.map(\.depth).max()!)
        for model in models {
            let depthOf = model.depthMapper()
            let verts = model.mesh.vertices.map { v in Vec3(model.materialXY(v), z: depthOf(v.z)) }
            let idx = model.mesh.indices
            map.depths.withUnsafeMutableBufferPointer { buf in
                var t = 0
                while t + 2 < idx.count {
                    let tri = [verts[Int(idx[t])], verts[Int(idx[t + 1])], verts[Int(idx[t + 2])]]
                    t += 3
                    rasterTriangle(tri, origin: area.min, cs: cellSize, cols: cols, rows: rows, buf: buf)
                }
            }
        }
        return map
    }

    /// Lowers every cell the triangle touches to the triangle's shallowest depth inside that
    /// cell's square (exact: min of a linear function over triangle ∩ square is at a vertex of
    /// the clipped polygon). Vertical triangles are handled too (their clip is a segment).
    private static func rasterTriangle(_ tri: [Vec3], origin: Vec2, cs: Double, cols: Int, rows: Int,
                                       buf: UnsafeMutableBufferPointer<Double>) {
        let minX = min(tri[0].x, tri[1].x, tri[2].x), maxX = max(tri[0].x, tri[1].x, tri[2].x)
        let minY = min(tri[0].y, tri[1].y, tri[2].y), maxY = max(tri[0].y, tri[1].y, tri[2].y)
        let i0 = max(0, Int(floor((minX - origin.x) / cs + 0.5)))
        let i1 = min(cols - 1, Int(floor((maxX - origin.x) / cs + 0.5)))
        let j0 = max(0, Int(floor((minY - origin.y) / cs + 0.5)))
        let j1 = min(rows - 1, Int(floor((maxY - origin.y) / cs + 0.5)))
        guard i0 <= i1, j0 <= j1 else { return }
        let half = cs / 2
        let triMin = min(tri[0].z, tri[1].z, tri[2].z)
        for j in j0...j1 {
            let cy = origin.y + Double(j) * cs
            for i in i0...i1 {
                let k = j * cols + i
                if buf[k] <= triMin { continue } // cannot get shallower
                let cx = origin.x + Double(i) * cs
                if let d = minDepth(of: tri, inBox: cx - half, cx + half, cy - half, cy + half), d < buf[k] {
                    buf[k] = d
                }
            }
        }
    }

    /// Minimum depth of the polygon clipped to the axis-aligned box, or nil if disjoint.
    static func minDepth(of poly: [Vec3], inBox x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Double? {
        // Fast path: every vertex inside the box.
        if poly.allSatisfy({ $0.x >= x0 && $0.x <= x1 && $0.y >= y0 && $0.y <= y1 }) {
            return poly.map(\.z).min()
        }
        var p = poly
        p = clip(p) { $0.x - x0 }
        p = clip(p) { x1 - $0.x }
        p = clip(p) { $0.y - y0 }
        p = clip(p) { y1 - $0.y }
        return p.map(\.z).min()
    }

    /// Sutherland–Hodgman against the half-plane `inside(v) >= 0`, interpolating depth.
    private static func clip(_ poly: [Vec3], _ inside: (Vec3) -> Double) -> [Vec3] {
        guard !poly.isEmpty else { return [] }
        var out: [Vec3] = []
        out.reserveCapacity(poly.count + 2)
        var prev = poly[poly.count - 1]
        var prevIn = inside(prev)
        for cur in poly {
            let curIn = inside(cur)
            if curIn >= 0 {
                if prevIn < 0 { out.append(prev + (cur - prev) * (prevIn / (prevIn - curIn))) }
                out.append(cur)
            } else if prevIn >= 0 {
                out.append(prev + (cur - prev) * (prevIn / (prevIn - curIn)))
            }
            prev = cur; prevIn = curIn
        }
        return out
    }
}
