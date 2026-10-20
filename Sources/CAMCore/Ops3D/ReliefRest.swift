import CADCore
import Foundation

/// 3D rest machining: where a smaller finishing tool still has material to cut after a larger
/// tool finished the same surface.
///
/// On the heightmap grid: the larger tool's drop depth at every cell gives the surface it leaves
/// behind (the upper envelope of its tip shape over all grid positions); the smaller tool is then
/// dropped onto both that surface and the model. Cells where it would sit deeper on the model by
/// more than `threshold` need rest machining. The mask is grown by `margin` (so passes overlap the
/// edges), contoured and clipped to the boundary.
///
/// All grid passes use the drop-cutter's rule (each cell square is reached at its point nearest
/// the tool axis), so the same tool dropped onto the surface it left lands exactly where it was.
enum ReliefRest {
    static func region(map: ReliefHeightmap, boundary: [[Vec2]], tool: Tool, previousTool: Tool, margin: Double,
                       threshold: Double, tolerance: Double) -> [[Vec2]] {
        let cols = map.columns, rows = map.rows
        guard cols > 0, rows > 0 else { return [] }
        let bigOffsets = offsets(CutterProfile(tool: previousTool), cellSize: map.cellSize)
        let smallOffsets = offsets(CutterProfile(tool: tool), cellSize: map.cellSize)

        let bigTip = sweep(map.depths, cols: cols, rows: rows, offsets: bigOffsets, deepest: false)
        // Surface left by the larger tool, never deeper than the model.
        var left = sweep(bigTip, cols: cols, rows: rows, offsets: bigOffsets, deepest: true)
        for n in left.indices { left[n] = min(left[n], map.depths[n]) }
        let onModel = sweep(map.depths, cols: cols, rows: rows, offsets: smallOffsets, deepest: false)
        let onLeft = sweep(left, cols: cols, rows: rows, offsets: smallOffsets, deepest: false)

        var mask = ReliefHeightmap(origin: map.origin, cellSize: map.cellSize, columns: cols, rows: rows, baseDepth: 0)
        var any = false
        for n in mask.depths.indices where onModel[n] > onLeft[n] + threshold { mask.depths[n] = -1; any = true }
        guard any else { return [] }
        // Grow the mask: the minimum of -mask within `margin` is -1 near any rest cell.
        var grown = mask.eroded(radius: max(0, margin))
        for n in grown.depths.indices { grown.depths[n] = -grown.depths[n] }
        let rest = Polygon2D.region(fromLoops: MarchingSquares.loops(grown, threshold: 0.5))
        let clip = Polygon2D.region(fromLoops: boundary)
        return GeomKernel.boolean(.intersection, subject: rest, clip: clip, fillRule: .evenOdd)
            .filter { $0.count > 2 && abs(Polygon2D.signedArea($0)) > tolerance * tolerance }
    }

    /// Cell offsets a cutter centred on a cell reaches, with the cutter surface height at each
    /// cell square's nearest point.
    static func offsets(_ cutter: CutterProfile, cellSize cs: Double) -> [(di: Int, dj: Int, h: Double)] {
        let k = Int(ceil((cutter.radius + cs / 2) / cs))
        var out: [(di: Int, dj: Int, h: Double)] = []
        for dj in -k...k {
            for di in -k...k {
                let dx = max(0, Double(abs(di)) * cs - cs / 2), dy = max(0, Double(abs(dj)) * cs - cs / 2)
                let r = (dx * dx + dy * dy).squareRoot()
                if r <= cutter.radius + 1e-12 { out.append((di, dj, cutter.height(at: r))) }
            }
        }
        return out
    }

    /// `deepest == false`: drop depth of the cutter at every cell, min over offsets of
    /// `v[c + o] + h(o)`. `deepest == true`: envelope of tool tips `v`, max over offsets of
    /// `v[c + o] - h(o)`. Cells outside the grid are ignored.
    static func sweep(_ v: [Double], cols: Int, rows: Int, offsets: [(di: Int, dj: Int, h: Double)],
                      deepest: Bool) -> [Double] {
        var out = [Double](repeating: deepest ? -.infinity : .infinity, count: v.count)
        v.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for o in offsets {
                    let i0 = max(0, -o.di), i1 = min(cols, cols - o.di)
                    let j0 = max(0, -o.dj), j1 = min(rows, rows - o.dj)
                    guard i0 < i1, j0 < j1 else { continue }
                    let shift = o.dj * cols + o.di
                    for j in j0..<j1 {
                        let row = j * cols
                        if deepest {
                            for c in (row + i0)..<(row + i1) {
                                let cand = src[c + shift] - o.h
                                if cand > dst[c] { dst[c] = cand }
                            }
                        } else {
                            for c in (row + i0)..<(row + i1) {
                                let cand = src[c + shift] + o.h
                                if cand < dst[c] { dst[c] = cand }
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}
