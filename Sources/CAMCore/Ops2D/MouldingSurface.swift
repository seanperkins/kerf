import CADCore
import Foundation

/// The surface a moulding leaves, as a heightmap, so curved and cornered rails can be cut with
/// a full 2D drop-cutter instead of the 1D straight-rail approximation (toolpaths-2d round 2).
///
/// A point's depth is the section depth at its distance from the rail (on the moulded side:
/// left/right of open rails, inside closed rails). Where several rails reach a point the
/// shallowest wins (no rail's profile is ever cut into). Just behind a rail (within the tool's
/// reach) the surface is the section's depth at the rail, as in the 1D model. Every cell holds
/// the shallowest depth anywhere in its square, so the drop-cutter cannot gouge between cells.
enum MouldingSurface {
    static func heightmap(_ profile: MouldingOperation.SectionProfile, closed: [[Vec2]], open: [[Vec2]],
                          left: Bool, toolRadius r: Double, step: Double, tolerance: Double) throws -> ReliefHeightmap {
        let width = profile.width
        let all = closed.flatMap { $0 } + open.flatMap { $0 }
        guard !all.isEmpty else { throw CAMError.noGeometry }
        let reachW = width + r
        var area = Rect2(points: all).insetBy(-(reachW + 2 * r))
        // Resolution: fine enough for the tool and stepover, capped at ~4M cells.
        var cell = max(min(step / 2, r / 4, width / 32), tolerance * 2)
        cell = max(cell, (area.width * area.height / 4_000_000).squareRoot())
        area = area.insetBy(-cell)
        let cols = Int(ceil(area.width / cell)) + 1
        let rows = Int(ceil(area.height / cell)) + 1
        guard cols * rows <= ReliefHeightmap.maxCells else { throw CAMError.invalidParameter("The moulding area is too large") }
        let maxDepth = profile.samples.map(\.depth).max() ?? 0
        // Unreached cells never hold the tool up.
        var map = ReliefHeightmap(origin: area.min, cellSize: cell, columns: cols, rows: rows,
                                  baseDepth: maxDepth + 1e6)
        let window = WindowMin(profile, halfWidth: cell * 0.5 * 2.0.squareRoot(), cell: cell)
        let n = cols * rows
        let reach = r + cell // "just behind the rail" band

        // Open rails: nearest distance on the moulded side (ok) and on the other side (bad).
        if !open.isEmpty {
            var tOK = [Double](repeating: .infinity, count: n)
            var tBad = [Double](repeating: .infinity, count: n)
            for line in open {
                for (a, b) in zip(line, line.dropFirst()) {
                    visit(a, b, grow: reachW + cell, map: map) { idx, p in
                        let (d, cross) = distance(p, a, b)
                        let ok = left ? cross >= 0 : cross <= 0
                        if ok { if d < tOK[idx] { tOK[idx] = d } } else if d < tBad[idx] { tBad[idx] = d }
                    }
                }
            }
            for idx in 0..<n {
                if tOK[idx] <= tBad[idx], tOK[idx] <= reachW + cell {
                    map.depths[idx] = min(map.depths[idx], window.depth(at: tOK[idx]))
                } else if tBad[idx] <= reach {
                    map.depths[idx] = min(map.depths[idx], window.depth(at: 0))
                }
            }
        }
        // Closed rails: the inside is moulded; the band just outside sits at the rail depth.
        if !closed.isEmpty {
            var t = [Double](repeating: .infinity, count: n)
            for loop in closed {
                for (a, b) in zip(loop, loop.dropFirst() + [loop[0]]) {
                    visit(a, b, grow: reachW + cell, map: map) { idx, p in
                        let d = distance(p, a, b).0
                        if d < t[idx] { t[idx] = d }
                    }
                }
            }
            for j in 0..<rows {
                let y = map.origin.y + Double(j) * cell
                let spans = insideSpans(closed, y: y)
                for i in 0..<cols {
                    let idx = j * cols + i
                    let x = map.origin.x + Double(i) * cell
                    let inside = spans.contains { x >= $0.0 && x <= $0.1 }
                    if inside {
                        map.depths[idx] = min(map.depths[idx], window.depth(at: min(t[idx], reachW + cell)))
                    } else if t[idx] <= reach {
                        map.depths[idx] = min(map.depths[idx], window.depth(at: 0))
                    }
                }
            }
        }
        return map
    }

    /// Calls `body` for every cell within `grow` of segment a–b.
    private static func visit(_ a: Vec2, _ b: Vec2, grow: Double, map: ReliefHeightmap, _ body: (Int, Vec2) -> Void) {
        let cs = map.cellSize
        let i0 = max(0, Int(floor((min(a.x, b.x) - grow - map.origin.x) / cs)))
        let i1 = min(map.columns - 1, Int(ceil((max(a.x, b.x) + grow - map.origin.x) / cs)))
        let j0 = max(0, Int(floor((min(a.y, b.y) - grow - map.origin.y) / cs)))
        let j1 = min(map.rows - 1, Int(ceil((max(a.y, b.y) + grow - map.origin.y) / cs)))
        guard i0 <= i1, j0 <= j1 else { return }
        for j in j0...j1 {
            for i in i0...i1 { body(j * map.columns + i, map.position(i, j)) }
        }
    }

    /// Distance from p to segment a–b, and the side (cross product sign: + = left of a→b).
    private static func distance(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> (Double, Double) {
        let d = b - a
        let len2 = d.dot(d)
        let t = len2 > 1e-24 ? min(max((p - a).dot(d) / len2, 0), 1) : 0
        let q = a + d * t
        return (p.distance(to: q), d.cross(p - a))
    }

    /// Even-odd x-spans of the closed loops on the horizontal line y.
    private static func insideSpans(_ loops: [[Vec2]], y: Double) -> [(Double, Double)] {
        var xs: [Double] = []
        for loop in loops {
            var j = loop.count - 1
            for i in 0..<loop.count {
                let a = loop[i], b = loop[j]
                if (a.y > y) != (b.y > y) { xs.append((b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) }
                j = i
            }
        }
        xs.sort()
        return stride(from: 0, to: xs.count - 1, by: 2).map { (xs[$0], xs[$0 + 1]) }
    }

    /// Shallowest section depth within ±halfWidth of an offset (linear sections reach their
    /// minimum at a sample or an end of the window, so both are included).
    struct WindowMin {
        let start: Double
        let g: Double
        let values: [Double]

        init(_ profile: MouldingOperation.SectionProfile, halfWidth h: Double, cell: Double) {
            let g = max(cell / 4, profile.width / 20_000)
            let pad = h + g
            start = -pad
            self.g = g
            let count = Int(ceil((profile.width + 2 * pad) / g)) + 1
            var raw = (0..<count).map { profile.depth(at: -pad + Double($0) * g) }
            for s in profile.samples { // samples between grid points
                let k = Int(((s.t + pad) / g).rounded(.down))
                for q in [k, k + 1] where raw.indices.contains(q) { raw[q] = min(raw[q], s.depth) }
            }
            let k = Int(ceil(pad / g))
            values = raw.indices.map { i in raw[max(0, i - k)...min(raw.count - 1, i + k)].min()! }
        }

        func depth(at t: Double) -> Double {
            let x = (t - start) / g
            let i0 = min(max(Int(x.rounded(.down)), 0), values.count - 1)
            let i1 = min(i0 + 1, values.count - 1)
            return min(values[i0], values[i1])
        }
    }
}
