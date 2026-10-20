import CADCore
import Foundation

/// Accumulates machine `Move`s for one tool while enforcing the toolpath conventions:
/// first move is a rapid at safe Z, every XY rapid happens at safe Z (retracting first), and
/// `build` leaves the tool at safe Z. Callers work in material-frame XY and depth; ALL Z math
/// goes through `MachineCoordinates`, so both Z-zero modes come out right.
public struct ToolpathBuilder {
    public let coords: MachineCoordinates
    public let feedRate: Double
    public let plungeRate: Double
    /// Chordal tolerance; arcs are fitted within `2 × tolerance` when `fitArcs` is on.
    public var tolerance: Double
    public var fitArcs: Bool
    /// Gap above already-cleared material down to which the tool may rapid before feeding.
    public var approachGap: Double

    public private(set) var moves: [Move] = []
    /// Current position (material XY, depth) — nil before the first move.
    public private(set) var position: CutPoint?

    public init(coords: MachineCoordinates, tool: Tool, units: LengthUnit, tolerance: Double, fitArcs: Bool = true) {
        self.coords = coords
        feedRate = tool.feedRate
        plungeRate = tool.plungeRate
        self.tolerance = tolerance
        self.fitArcs = fitArcs
        approachGap = min(coords.job.safeZ, units == .inch ? 0.05 : 1.0)
    }

    /// Depth of the safe-Z plane (negative = above the top).
    public var safeDepth: Double { -coords.job.safeZ }
    private var eps: Double { tolerance * 1e-3 }
    public var isAtSafeZ: Bool { position.map { $0.depth <= safeDepth + eps } ?? true }

    // MARK: Travel

    /// Retract to safe Z (if below it).
    public mutating func retract() {
        guard let p = position, p.depth > safeDepth + eps else { return }
        moves.append(.rapid(to: coords.machineAtSafeZ(p.xy)))
        position = CutPoint(p.xy, depth: safeDepth)
    }

    /// Positions the tool above `xy` at safe Z (retracting first when needed). No-op if already
    /// above `xy`.
    public mutating func travel(to xy: Vec2) {
        if let p = position, p.xy.distance(to: xy) <= eps { return }
        retract()
        moves.append(.rapid(to: coords.machineAtSafeZ(xy)))
        position = CutPoint(xy, depth: safeDepth)
    }

    /// Moves straight down at the current XY to `depth`. Rapids down to `approachGap` above
    /// `clearedDepth` (material known to be removed there), then feeds at the plunge rate.
    public mutating func plunge(to depth: Double, clearedDepth: Double = 0) {
        guard let p = position else { preconditionFailure("plunge before travel") }
        guard depth > p.depth + eps else { return }
        let approach = min(clearedDepth - approachGap, depth)
        if approach > p.depth + eps {
            moves.append(.rapid(to: coords.machine(p.xy, depth: approach)))
        }
        moves.append(.linear(to: coords.machine(p.xy, depth: depth), feed: plungeRate))
        position = CutPoint(p.xy, depth: depth)
    }

    /// Travel to the first point of `points` (if not there) and plunge, then cut the rest.
    public mutating func cutChain(_ points: [CutPoint], clearedDepth: Double = 0) {
        guard let first = points.first else { return }
        if let p = position, p.xy.distance(to: first.xy) <= eps {
            if first.depth < p.depth - eps { feed(to: [first]) }
        } else {
            travel(to: first.xy)
        }
        plunge(to: first.depth, clearedDepth: clearedDepth)
        feed(to: Array(points.dropFirst()))
    }

    /// Feeds through `points` from the current position (lines, plus arcs where the depth is
    /// constant and `fitArcs` is on). Steep descents use the plunge rate.
    public mutating func feed(to points: [CutPoint]) {
        guard var cur = position else { preconditionFailure("feed before travel") }
        var pts = [cur]
        for q in points where !(q.xy.distance(to: pts.last!.xy) <= eps && abs(q.depth - pts.last!.depth) <= eps) {
            pts.append(q)
        }
        guard pts.count > 1 else { return }
        var i = 0
        while i < pts.count - 1 {
            // Constant-depth run starting at i.
            var j = i + 1
            while j < pts.count, abs(pts[j].depth - pts[i].depth) <= eps { j += 1 }
            let runEnd = j - 1
            if runEnd > i {
                emitFlat(Array(pts[i...runEnd]).map(\.xy), depth: pts[i].depth)
                cur = pts[runEnd]
                i = runEnd
            } else {
                emitLines([pts[i], pts[i + 1]])
                cur = pts[i + 1]
                i += 1
            }
        }
        position = cur
    }

    public mutating func dwell(_ seconds: Double) {
        if seconds > 0 { moves.append(.dwell(seconds: seconds)) }
    }

    /// Final moves: retract to safe Z.
    public mutating func finish() -> [Move] {
        retract()
        return moves
    }

    // MARK: Emission

    private mutating func emitFlat(_ xy: [Vec2], depth: Double) {
        let simplified = Self.mergeCollinear(xy, tolerance: tolerance * 0.05)
        if fitArcs, simplified.count > ArcFitter.minimumSegments {
            for seg in ArcFitter.fit(simplified, tolerance: tolerance * 2) {
                switch seg {
                case .line(let to):
                    moves.append(.linear(to: coords.machine(to, depth: depth), feed: feedRate))
                case .arc(let to, let c, let cw):
                    let m = coords.machine(to, depth: depth)
                    let cc = coords.machineXY(c)
                    moves.append(cw ? .arcCW(to: m, center: cc, feed: feedRate) : .arcCCW(to: m, center: cc, feed: feedRate))
                }
            }
        } else {
            for p in simplified.dropFirst() {
                moves.append(.linear(to: coords.machine(p, depth: depth), feed: feedRate))
            }
        }
    }

    private mutating func emitLines(_ pts: [CutPoint]) {
        for (a, b) in zip(pts, pts.dropFirst()) {
            let dz = b.depth - a.depth
            let steep = dz > 0 && a.xy.distance(to: b.xy) < dz
            moves.append(.linear(to: coords.machine(b.xy, depth: b.depth), feed: steep ? plungeRate : feedRate))
        }
    }

    /// Drops vertices that lie on the straight line between their neighbours.
    static func mergeCollinear(_ p: [Vec2], tolerance: Double) -> [Vec2] {
        guard p.count > 2 else { return p }
        var out = [p[0]]
        var anchor = p[0]
        var pending: [Vec2] = []
        for q in p.dropFirst() {
            // Can every pending point be dropped if we go straight from anchor to q?
            let ok = pending.allSatisfy { m in
                let (c, t) = Polygon2D.closestPoint(onSegment: anchor, q, to: m)
                return t > 0 && t < 1 && c.distance(to: m) <= tolerance
            }
            if ok {
                pending.append(q)
            } else {
                let last = pending.last!
                out.append(last)
                anchor = last
                pending = [q]
            }
        }
        if let last = pending.last { out.append(last) }
        return out
    }
}
