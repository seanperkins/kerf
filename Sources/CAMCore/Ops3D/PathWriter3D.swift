import CADCore
import Foundation

/// Accumulates moves for one tool in the material frame (XY + depth below the top) and converts
/// them to machine coordinates, enforcing the `Toolpath` conventions: start with a rapid at safe
/// Z, every XY rapid at safe Z, end at safe Z.
struct PathWriter3D {
    let coords: MachineCoordinates
    let feedRate: Double
    let plungeRate: Double
    /// Height above the material top that rapid descents stop at before plunging.
    let clearance: Double

    private(set) var moves: [Move] = []
    /// Current position (material XY, depth); nil before the first move.
    private(set) var position: (xy: Vec2, depth: Double)?

    init(coords: MachineCoordinates, feedRate: Double, plungeRate: Double, clearance: Double) {
        self.coords = coords; self.feedRate = feedRate; self.plungeRate = plungeRate; self.clearance = clearance
    }

    /// Depth value of the safe plane (negative: above the top).
    var safeDepth: Double { -coords.job.safeZ }

    var isAtSafeZ: Bool { position.map { $0.depth <= safeDepth + 1e-9 } ?? true }

    mutating func retract() {
        guard let p = position, p.depth > safeDepth + 1e-9 else { return }
        emitRapid(p.xy, depth: safeDepth)
    }

    /// Retracts if needed and rapids to `xy` at safe Z.
    mutating func rapid(to xy: Vec2) {
        retract()
        if let p = position, p.xy.isApproximatelyEqual(to: xy, tolerance: 1e-9) { return }
        emitRapid(xy, depth: safeDepth)
    }

    /// From safe Z above the current XY: rapid down to `approachDepth` (default: `clearance` above
    /// the top), then plunge at the plunge rate to `depth`.
    mutating func plunge(to depth: Double, approachDepth: Double? = nil) {
        guard let p = position else { return }
        let approach = min(approachDepth ?? -clearance, depth)
        if approach > p.depth + 1e-9 { emitRapid(p.xy, depth: approach) }
        if let now = position, now.depth < depth - 1e-9 {
            emitLinear(p.xy, depth: depth, feed: plungeRate)
        }
    }

    /// Goes to `(xy, depth)` from anywhere: rapid above it, then plunge.
    mutating func enter(at xy: Vec2, depth: Double, approachDepth: Double? = nil) {
        rapid(to: xy)
        plunge(to: depth, approachDepth: approachDepth)
    }

    /// Cutting move; a descent steeper than 45 degrees uses the plunge rate.
    mutating func cut(to xy: Vec2, depth: Double) {
        guard let p = position else { return }
        let horizontal = p.xy.distance(to: xy)
        if horizontal < 1e-12 && abs(depth - p.depth) < 1e-12 { return }
        let isPlunge = depth - p.depth > horizontal
        emitLinear(xy, depth: depth, feed: isPlunge ? plungeRate : feedRate)
    }

    mutating func cut(through points: [Vec3]) {
        for q in points { cut(to: q.xy, depth: q.z) }
    }

    /// Retracts and returns the finished move list.
    mutating func finish() -> [Move] {
        retract()
        return moves
    }

    private mutating func emitRapid(_ xy: Vec2, depth: Double) {
        moves.append(.rapid(to: coords.machine(xy, depth: depth)))
        position = (xy, depth)
    }

    private mutating func emitLinear(_ xy: Vec2, depth: Double, feed: Double) {
        moves.append(.linear(to: coords.machine(xy, depth: depth), feed: feed))
        position = (xy, depth)
    }
}

enum Polyline3D {
    /// Douglas–Peucker simplification of a 3D polyline (x, y, depth): removed points lie within
    /// `tolerance` of the kept chords.
    static func simplify(_ pts: [Vec3], tolerance: Double) -> [Vec3] {
        guard pts.count > 2, tolerance > 0 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let pa = pts[a], ab = pts[b] - pa
            let len2 = ab.dot(ab)
            var worst = -1.0, worstIndex = -1
            for k in (a + 1)..<b {
                let ap = pts[k] - pa
                let d2: Double
                if len2 < 1e-24 {
                    d2 = ap.dot(ap)
                } else {
                    let t = min(1, max(0, ap.dot(ab) / len2))
                    let off = ap - ab * t
                    d2 = off.dot(off)
                }
                if d2 > worst { worst = d2; worstIndex = k }
            }
            if worst > tolerance * tolerance {
                keep[worstIndex] = true
                stack.append((a, worstIndex)); stack.append((worstIndex, b))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    /// Points from `a` to `b` (inclusive) no further apart than `step`.
    static func sample(from a: Vec2, to b: Vec2, step: Double) -> [Vec2] {
        let n = max(1, Int(ceil(a.distance(to: b) / max(step, 1e-9))))
        return (0...n).map { a.lerp(to: b, Double($0) / Double(n)) }
    }
}
