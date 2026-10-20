import CADCore
import Foundation

/// A 3D cutting polyline in the material frame: `x`,`y` in document units, `z` = depth
/// below the material top (positive into the stock).
struct VCarveStroke: Hashable {
    var points: [Vec3]
    /// Closed loops repeat their first point at the end.
    var isClosed: Bool

    var maxDepth: Double { points.map(\.z).max() ?? 0 }
}

enum VCarveStrokes {
    /// Depth levels for the cut: evenly spaced, at most `passDepth` apart, last = `total`.
    static func passLevels(total: Double, passDepth: Double?) -> [Double] {
        guard let step = passDepth, step > 1e-9, total > step + 1e-9 else { return [total] }
        return DepthSettings(startDepth: 0, cutDepth: total, passDepth: step).passDepths(toolStepdown: step)
    }

    /// Strokes for every pass level, in pass order. Pass k cuts only where the target depth
    /// exceeds level k-1 (shallower parts were finished earlier) and clamps at level k.
    static func multiPass(_ strokes: [VCarveStroke], levels: [Double]) -> [[VCarveStroke]] {
        var previous = -Double.infinity
        var result: [[VCarveStroke]] = []
        for level in levels {
            var pass: [VCarveStroke] = []
            for s in strokes { pass.append(contentsOf: clip(s, above: previous, clampAt: level)) }
            result.append(pass)
            previous = level
        }
        return result
    }

    private static func clip(_ s: VCarveStroke, above floor: Double, clampAt level: Double) -> [VCarveStroke] {
        let eps = 1e-7
        let keep = s.points.map { $0.z > floor + eps }
        if keep.allSatisfy({ $0 }) {
            return [VCarveStroke(points: s.points.map { Vec3($0.xy, z: min($0.z, level)) }, isClosed: s.isClosed)]
        }
        var out: [VCarveStroke] = []
        var i = 0
        let n = s.points.count
        while i < n {
            guard keep[i] else { i += 1; continue }
            var j = i
            while j + 1 < n, keep[j + 1] { j += 1 }
            let lo = max(0, i - 1), hi = min(n - 1, j + 1)
            let pts = s.points[lo...hi].map { Vec3($0.xy, z: min($0.z, level)) }
            if pts.count >= 2 { out.append(VCarveStroke(points: pts, isClosed: false)) }
            i = j + 1
        }
        return out
    }

    /// Removes points that lie within `tolerance` of the 3D segment joining their neighbours.
    static func simplified(_ pts: [Vec3], tolerance: Double) -> [Vec3] {
        guard pts.count > 2 else { return pts }
        var out: [Vec3] = [pts[0]]
        for i in 1..<(pts.count - 1) {
            let a = out.last!, b = pts[i], c = pts[i + 1]
            if distance(b, toSegment: a, c) > tolerance { out.append(b) }
        }
        out.append(pts[pts.count - 1])
        return out
    }

    private static func distance(_ p: Vec3, toSegment a: Vec3, _ b: Vec3) -> Double {
        let ab = Vec3(b.x - a.x, b.y - a.y, b.z - a.z)
        let ap = Vec3(p.x - a.x, p.y - a.y, p.z - a.z)
        let len2 = ab.dot(ab)
        let t = len2 > 0 ? max(0, min(1, ap.dot(ab) / len2)) : 0
        let q = Vec3(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t)
        return p.distance(to: q)
    }

    /// Greedy nearest-neighbour order; open strokes may be reversed.
    static func ordered(_ strokes: [VCarveStroke], from start: Vec2 = .zero) -> [VCarveStroke] {
        var pool = strokes
        var out: [VCarveStroke] = []
        var cursor = start
        while !pool.isEmpty {
            var best = (index: 0, reversed: false, d: Double.infinity)
            for (i, s) in pool.enumerated() {
                let d0 = s.points[0].xy.distance(to: cursor)
                if d0 < best.d { best = (i, false, d0) }
                if !s.isClosed {
                    let d1 = s.points[s.points.count - 1].xy.distance(to: cursor)
                    if d1 < best.d { best = (i, true, d1) }
                }
            }
            var s = pool.remove(at: best.index)
            if best.reversed { s.points.reverse() }
            cursor = s.points[s.points.count - 1].xy
            out.append(s)
        }
        return out
    }

    /// Closed loops (no repeated point) at a constant depth.
    static func loops(_ polygons: [[Vec2]], depth: Double) -> [VCarveStroke] {
        polygons.filter { $0.count > 2 }.map { poly in
            VCarveStroke(points: (poly + [poly[0]]).map { Vec3($0, z: depth) }, isClosed: true)
        }
    }
}

/// Emits machine moves for strokes, honouring the toolpath conventions: start with a rapid
/// at safe Z, retract before every XY rapid, plunge at the plunge rate, end at safe Z.
struct VCarveMoveWriter {
    let coords: MachineCoordinates
    let feed: Double
    let plunge: Double
    /// Strokes whose start is within this distance of the current position are joined
    /// without lifting.
    let linkTolerance: Double
    private(set) var moves: [Move] = []
    private var position: Vec3?

    init(coords: MachineCoordinates, feed: Double, plunge: Double, linkTolerance: Double) {
        self.coords = coords; self.feed = feed; self.plunge = plunge; self.linkTolerance = linkTolerance
    }

    mutating func cut(_ stroke: VCarveStroke) {
        guard let first = stroke.points.first else { return }
        let safeDepth = -coords.job.safeZ
        if let p = position, p.z > safeDepth + 1e-9, p.xy.distance(to: first.xy) <= linkTolerance {
            if p != first { linear(first, plunging: first.z > p.z + 1e-9) }
        } else {
            retract()
            if position?.xy != first.xy { moves.append(.rapid(to: coords.machineAtSafeZ(first.xy))) }
            position = Vec3(first.xy, z: safeDepth)
            // Job plunge gap: rapid down to it before feeding (default: plunge from safe Z).
            if let g = coords.job.plungeGap {
                let gap = coords.job.effectivePlungeGap(default: g)
                if gap < coords.job.safeZ - 1e-9, first.z > -gap + 1e-9 {
                    moves.append(.rapid(to: coords.machine(first.xy, depth: -gap)))
                    position = Vec3(first.xy, z: -gap)
                }
            }
            linear(first, plunging: true)
        }
        for p in stroke.points.dropFirst() { linear(p, plunging: false) }
    }

    /// Lifts to safe Z (no-op if already there).
    mutating func retract() {
        let safeDepth = -coords.job.safeZ
        guard let p = position, p.z > safeDepth + 1e-12 else { return }
        moves.append(.rapid(to: coords.machineAtSafeZ(p.xy)))
        position = Vec3(p.xy, z: safeDepth)
    }

    private mutating func linear(_ p: Vec3, plunging: Bool) {
        moves.append(.linear(to: coords.machine(p.xy, depth: p.z), feed: plunging ? plunge : feed))
        position = p
    }

    /// Finished move list (ends at safe Z).
    mutating func finish() -> [Move] {
        retract()
        return moves
    }
}
