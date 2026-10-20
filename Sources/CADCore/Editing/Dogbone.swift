import Foundation

/// Corner relief ("dog-bone" / "T-bone") for parts cut with a round bit.
///
/// A round cutter cannot reach a sharp inside corner: it leaves a fillet of its own radius. A
/// relief adds a small circular over-cut so the corner point itself is cut and a square-cornered
/// mating part fits. Only corners between two straight segments are relieved.
public enum Dogbone {
    public enum Style: String, Codable, CaseIterable, Sendable {
        /// Circle centred on the corner bisector (symmetric over-cut).
        case dogbone
        /// Circle centred on the longer adjacent edge: the over-cut runs sideways past that edge,
        /// leaving the shorter edge straight up to the corner.
        case tBoneLong
        /// Circle centred on the shorter adjacent edge (over-cut past the shorter edge).
        case tBoneShort
    }

    /// Which side of the vector the cutter removes.
    public enum CutSide: String, Codable, CaseIterable, Sendable {
        /// The shape is a part cut out along its outline (profile outside, holes cut inside):
        /// corners that point into the part's material from outside are relieved.
        case part
        /// The shape is an opening/pocket that the cutter clears (slots, mortises).
        case opening
    }

    /// Paths with relief added to every reachable inside corner sharper than `maxAngle` degrees.
    /// `radius` is the cutter radius. Open paths and curved corners are returned unchanged.
    public static func apply(to paths: [Path], radius: Double, style: Style = .dogbone, side: CutSide,
                             maxAngle: Double = 135, tolerance: Double = Path.defaultTolerance) -> [Path] {
        guard radius > 0 else { return paths }
        let depths = PathGeometry.nestingDepths(paths, tolerance: tolerance)
        return paths.indices.map { i in
            let p = paths[i]
            guard p.isClosed, p.segments.count >= 2 else { return p }
            // Region of the shape on the left of the path?
            let ccw = p.signedArea(tolerance: tolerance) > 0
            let regionLeft = depths[i].isMultiple(of: 2) ? ccw : !ccw
            let cutOnLeft = (side == .opening) == regionLeft
            return relieve(p, radius: radius, style: style, cutOnLeft: cutOnLeft, maxAngle: maxAngle)
        }
    }

    /// Number of corners `apply` would relieve (for UI feedback).
    public static func reliefCount(_ paths: [Path], radius: Double, style: Style = .dogbone, side: CutSide,
                                   maxAngle: Double = 135) -> Int {
        let out = apply(to: paths, radius: radius, style: style, side: side, maxAngle: maxAngle)
        func arcs(_ ps: [Path]) -> Int {
            ps.reduce(0) { $0 + $1.segments.filter { if case .arc = $0 { return true }; return false }.count }
        }
        return arcs(out) - arcs(paths)
    }

    // MARK: - Internals

    private struct Relief {
        var a: Vec2   // on the incoming edge
        var b: Vec2   // on the outgoing edge
        var arc: PathSegment
        var trimIn: Double
        var trimOut: Double
    }

    static func relieve(_ path: Path, radius r: Double, style: Style, cutOnLeft: Bool, maxAngle: Double) -> Path {
        var segs = path.segments
        if !segs.last!.end.isApproximatelyEqual(to: path.start, tolerance: 1e-9) { segs.append(.line(to: path.start)) }
        let n = segs.count
        func vertex(_ k: Int) -> Vec2 { k == 0 ? path.start : segs[k - 1].end }
        func isLine(_ j: Int) -> Bool { if case .line = segs[j] { return true }; return false }
        func length(_ j: Int) -> Double { vertex(j).distance(to: vertex((j + 1) % n)) }

        var reliefs = [Relief?](repeating: nil, count: n)
        for k in 0..<n {
            let jin = (k - 1 + n) % n, jout = k
            guard isLine(jin), isLine(jout) else { continue }
            let p = vertex(k)
            let lin = length(jin), lout = length(jout)
            guard lin > 1e-12, lout > 1e-12 else { continue }
            let d1 = (p - vertex(jin)) / lin, d2 = (vertex((k + 1) % n) - p) / lout
            let turn = d1.cross(d2)
            // Unreachable corner: the cut side is the narrow side of the turn.
            guard cutOnLeft ? turn > 1e-9 : turn < -1e-9 else { continue }
            let f1 = -d1, f2 = d2
            let angle = acos(max(-1, min(1, f1.dot(f2)))) * 180 / .pi
            guard angle <= maxAngle + 1e-9 else { continue }
            let bisector = (f1 + f2).normalized
            let u: Vec2
            switch style {
            case .dogbone: u = bisector
            case .tBoneLong: u = lin >= lout ? f1 : f2
            case .tBoneShort: u = lin >= lout ? f2 : f1
            }
            let c = p + u * r
            let trimIn = max(0, 2 * r * f1.dot(u)), trimOut = max(0, 2 * r * f2.dot(u))
            let a = p + f1 * trimIn, b = p + f2 * trimOut
            // The arc goes round the side away from the cut (through the corner region).
            let away = c - bisector * r
            let cw = !ccwArcContains(from: a, to: b, center: c, point: away)
            reliefs[k] = Relief(a: a, b: b, arc: .arc(to: b, center: c, clockwise: cw), trimIn: trimIn, trimOut: trimOut)
        }
        // Drop reliefs that would overrun a segment (both ends of a short edge).
        var changed = true
        while changed {
            changed = false
            for j in 0..<n {
                let s = reliefs[j]?.trimOut ?? 0, e = reliefs[(j + 1) % n]?.trimIn ?? 0
                if s + e > length(j) + 1e-9 {
                    if e >= s { reliefs[(j + 1) % n] = nil } else { reliefs[j] = nil }
                    changed = true
                }
            }
        }
        guard reliefs.contains(where: { $0 != nil }) else { return path }

        var out = Path(start: reliefs[0]?.b ?? path.start, isClosed: true)
        var cur = out.start
        for j in 0..<n {
            let next = (j + 1) % n
            if let rel = reliefs[next] {
                if !rel.a.isApproximatelyEqual(to: cur, tolerance: 1e-12) { out.segments.append(.line(to: rel.a)) }
                out.segments.append(rel.arc)
                cur = rel.b
            } else {
                out.segments.append(segs[j])
                cur = segs[j].end
            }
        }
        return out
    }

    /// True when the counter-clockwise arc from `a` to `b` around `center` passes `point`.
    static func ccwArcContains(from a: Vec2, to b: Vec2, center: Vec2, point: Vec2) -> Bool {
        func ang(_ v: Vec2) -> Double { atan2(v.y - center.y, v.x - center.x) }
        func sweep(_ x: Double) -> Double { var s = x - ang(a); while s < 0 { s += 2 * .pi }; return s }
        var toB = sweep(ang(b))
        if toB < 1e-12 { toB = 2 * .pi }
        return sweep(ang(point)) < toB
    }
}
