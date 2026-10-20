import Foundation

/// Node (anchor point) editing on a single `Path`.
///
/// All editing functions work on the *editable form* of a path (see `editable(_:)`): arcs are
/// converted to cubic Béziers and closed paths carry an explicit closing segment, so that
///
/// - anchor `k` is `start` for k == 0, otherwise `segments[k - 1].end`;
/// - a closed path has `segments.count` anchors (the last segment ends on anchor 0);
/// - an open path has `segments.count + 1` anchors;
/// - segment `k` runs from anchor `k` to anchor `k + 1` (wrapping to 0 when closed).
///
/// Node indices shown by the UI must come from the editable form so they stay valid across edits.
public enum PathNodes {
    public enum Handle: String, Codable, Hashable, Sendable {
        /// Control point of the incoming cubic next to the anchor (its `control2`).
        case incoming
        /// Control point of the outgoing cubic next to the anchor (its `control1`).
        case outgoing
    }

    // MARK: Editable form

    /// Arcs → cubics, and closed paths gain an explicit closing line when they do not already
    /// end on their start point. Geometry is unchanged (up to Bézier arc approximation).
    public static func editable(_ path: Path) -> Path {
        var out = Path(start: path.start, isClosed: path.isClosed)
        var cur = path.start
        for seg in path.segments {
            if case .arc(let to, let c, let cw) = seg {
                out.segments += Flattening.arcToCubics(from: cur, to: to, center: c, clockwise: cw)
            } else {
                out.segments.append(seg)
            }
            cur = seg.end
        }
        if out.isClosed, !out.segments.isEmpty, !out.end.isApproximatelyEqual(to: out.start, tolerance: 1e-9) {
            out.segments.append(.line(to: out.start))
        }
        if out.isClosed, let last = out.segments.indices.last {
            // Snap the closing point exactly onto the start.
            out.segments[last] = withEnd(out.segments[last], out.start)
        }
        return out
    }

    /// True when `path` already is in editable form (no arcs; closed paths end on start).
    public static func isEditable(_ path: Path) -> Bool {
        if path.segments.contains(where: { if case .arc = $0 { return true }; return false }) { return false }
        return !path.isClosed || path.segments.isEmpty || path.end == path.start
    }

    // MARK: Queries (editable form)

    public static func anchorCount(_ p: Path) -> Int {
        p.segments.isEmpty ? 1 : (p.isClosed ? p.segments.count : p.segments.count + 1)
    }

    public static func anchor(_ p: Path, _ k: Int) -> Vec2 { k == 0 ? p.start : p.segments[k - 1].end }

    public static func anchors(_ p: Path) -> [Vec2] { (0..<anchorCount(p)).map { anchor(p, $0) } }

    /// Segment ending at anchor `k` (nil for the first anchor of an open path).
    public static func incomingSegment(_ p: Path, _ k: Int) -> Int? {
        if k > 0 { return k - 1 }
        return p.isClosed && !p.segments.isEmpty ? p.segments.count - 1 : nil
    }

    /// Segment starting at anchor `k` (nil for the last anchor of an open path).
    public static func outgoingSegment(_ p: Path, _ k: Int) -> Int? {
        k < p.segments.count ? k : nil
    }

    /// Position of a Bézier handle of anchor `k`, if the adjacent segment is a cubic.
    public static func handle(_ p: Path, _ k: Int, _ h: Handle) -> Vec2? {
        switch h {
        case .incoming:
            guard let s = incomingSegment(p, k), case .cubic(_, _, let c2) = p.segments[s] else { return nil }
            return c2
        case .outgoing:
            guard let s = outgoingSegment(p, k), case .cubic(_, let c1, _) = p.segments[s] else { return nil }
            return c1
        }
    }

    /// True when both handles exist and are (anti-)collinear through the anchor.
    public static func isSmooth(_ p: Path, _ k: Int, angleTolerance: Double = 0.02) -> Bool {
        guard let a = handle(p, k, .incoming), let b = handle(p, k, .outgoing) else { return false }
        let o = anchor(p, k)
        let u = a - o, v = b - o
        guard u.length > 1e-12, v.length > 1e-12 else { return false }
        return abs(u.normalized.cross(v.normalized)) < angleTolerance && u.dot(v) < 0
    }

    // MARK: Edits (editable form in, editable form out)

    /// Moves anchor `k` to `point`; the anchor's own handles move with it.
    public static func moveAnchor(_ path: Path, _ k: Int, to point: Vec2) -> Path {
        var p = path
        let d = point - anchor(p, k)
        if k == 0 { p.start = point }
        if let s = incomingSegment(p, k) {
            p.segments[s] = withEnd(p.segments[s], point)
            if case .cubic(let e, let c1, let c2) = p.segments[s] { p.segments[s] = .cubic(to: e, control1: c1, control2: c2 + d) }
        }
        if let s = outgoingSegment(p, k), case .cubic(let e, let c1, let c2) = p.segments[s] {
            p.segments[s] = .cubic(to: e, control1: c1 + d, control2: c2)
        }
        return p
    }

    /// Moves a handle of anchor `k`. With `keepSmooth`, the opposite handle is rotated to stay
    /// collinear (its length is kept). No-op when the handle does not exist.
    public static func moveHandle(_ path: Path, _ k: Int, _ h: Handle, to point: Vec2, keepSmooth: Bool) -> Path {
        var p = path
        let o = anchor(p, k)
        func setHandle(_ which: Handle, _ v: Vec2) {
            switch which {
            case .incoming:
                if let s = incomingSegment(p, k), case .cubic(let e, let c1, _) = p.segments[s] {
                    p.segments[s] = .cubic(to: e, control1: c1, control2: v)
                }
            case .outgoing:
                if let s = outgoingSegment(p, k), case .cubic(let e, _, let c2) = p.segments[s] {
                    p.segments[s] = .cubic(to: e, control1: v, control2: c2)
                }
            }
        }
        guard handle(p, k, h) != nil else { return p }
        setHandle(h, point)
        let other: Handle = h == .incoming ? .outgoing : .incoming
        if keepSmooth, let q = handle(p, k, other) {
            let dir = (o - point).normalized
            if dir != .zero { setHandle(other, o + dir * (q - o).length) }
        }
        return p
    }

    /// Inserts an anchor on segment `s` at parameter `t` (0…1). The new anchor is index `s + 1`.
    /// Curves are split exactly (de Casteljau), so the shape does not change.
    public static func insertAnchor(_ path: Path, segment s: Int, t: Double) -> Path {
        var p = path
        let a = p.startOfSegment(s)
        let t = min(max(t, 0), 1)
        switch p.segments[s] {
        case .line(let to):
            let m = a.lerp(to: to, t)
            p.segments.replaceSubrange(s...s, with: [.line(to: m), .line(to: to)])
        case .cubic(let to, let c1, let c2):
            let (l, r) = splitCubic(a, c1, c2, to, t)
            p.segments.replaceSubrange(s...s, with: [l, r])
        case .arc(let to, let c, let cw):
            let sweep = Flattening.arcSweep(from: a, to: to, center: c, clockwise: cw)
            let ang = (a - c).angle + sweep * t
            let m = c + Vec2(cos(ang), sin(ang)) * a.distance(to: c)
            p.segments.replaceSubrange(s...s, with: [.arc(to: m, center: c, clockwise: cw), .arc(to: to, center: c, clockwise: cw)])
        }
        return p
    }

    /// Removes anchor `k`, joining its neighbours. Two adjacent curves merge into one curve that
    /// keeps the outer handles; otherwise the result is a straight line. Returns nil when the
    /// path would become degenerate (open < 2 anchors, closed < 3 anchors).
    public static func deleteAnchor(_ path: Path, _ k: Int) -> Path? {
        var p = path
        let n = anchorCount(p)
        if p.isClosed ? n <= 3 : n <= 2 { return nil }
        let inc = incomingSegment(p, k), out = outgoingSegment(p, k)
        switch (inc, out) {
        case (nil, .some):
            // First anchor of an open path: the second anchor becomes the start.
            p.start = p.segments[0].end
            p.segments.removeFirst()
        case (.some, nil):
            p.segments.removeLast()
        case (.some(let i), .some(let o)):
            let merged: PathSegment
            if case .cubic(_, let c1, _) = p.segments[i], case .cubic(let e, _, let c2) = p.segments[o] {
                merged = .cubic(to: e, control1: c1, control2: c2)
            } else {
                merged = .line(to: p.segments[o].end)
            }
            if k == 0 {
                // Closed path: drop the first anchor; the next anchor becomes the start.
                p.start = p.segments[o].end
                p.segments.removeFirst()
                p.segments[p.segments.count - 1] = merged
            } else {
                p.segments.replaceSubrange(i...o, with: [merged])
            }
        case (nil, nil):
            return nil
        }
        return p
    }

    /// Converts segment `s` to a straight line or to a cubic curve (control points at thirds).
    public static func convertSegment(_ path: Path, _ s: Int, toCurve: Bool) -> Path {
        var p = path
        let a = p.startOfSegment(s)
        let e = p.segments[s].end
        if toCurve {
            if case .line = p.segments[s] { p.segments[s] = .cubic(to: e, control1: a.lerp(to: e, 1.0 / 3), control2: a.lerp(to: e, 2.0 / 3)) }
        } else {
            p.segments[s] = .line(to: e)
        }
        return p
    }

    /// Makes anchor `k` smooth: both adjacent segments become curves whose handles are collinear
    /// (direction = from previous anchor to next anchor, lengths = a third of each segment).
    public static func makeSmooth(_ path: Path, _ k: Int) -> Path {
        guard let i = incomingSegment(path, k), let o = outgoingSegment(path, k) else { return path }
        var p = convertSegment(convertSegment(path, i, toCurve: true), o, toCurve: true)
        let n = anchorCount(p)
        let prev = anchor(p, (k - 1 + n) % n)
        let next = anchor(p, (k + 1) % n)
        let a = anchor(p, k)
        let dir = (next - prev).normalized
        guard dir != .zero else { return p }
        p = moveHandleRaw(p, k, .incoming, a - dir * (a.distance(to: prev) / 3))
        p = moveHandleRaw(p, k, .outgoing, a + dir * (a.distance(to: next) / 3))
        return p
    }

    /// Nearest point on the path to `q`: (segment, parameter, distance).
    public static func nearestSegment(_ path: Path, to q: Vec2, samples: Int = 48) -> (segment: Int, t: Double, distance: Double)? {
        guard !path.segments.isEmpty else { return nil }
        var best: (Int, Double, Double)?
        for s in path.segments.indices {
            let a = path.startOfSegment(s)
            let (t, d) = nearestOnSegment(path.segments[s], from: a, to: q, samples: samples)
            if d < (best?.2 ?? .infinity) { best = (s, t, d) }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }

    /// Point on segment `s` at parameter `t`.
    public static func point(_ path: Path, segment s: Int, t: Double) -> Vec2 {
        let a = path.startOfSegment(s)
        switch path.segments[s] {
        case .line(let to): return a.lerp(to: to, t)
        case .cubic(let to, let c1, let c2): return Flattening.cubicPoint(a, c1, c2, to, t)
        case .arc(let to, let c, let cw):
            let sweep = Flattening.arcSweep(from: a, to: to, center: c, clockwise: cw)
            let ang = (a - c).angle + sweep * t
            return c + Vec2(cos(ang), sin(ang)) * a.distance(to: c)
        }
    }

    // MARK: Helpers

    static func nearestOnSegment(_ seg: PathSegment, from a: Vec2, to q: Vec2, samples: Int) -> (Double, Double) {
        if case .line(let b) = seg {
            let ab = b - a
            let l2 = ab.lengthSquared
            let t = l2 > 0 ? min(max((q - a).dot(ab) / l2, 0), 1) : 0
            return (t, q.distance(to: a + ab * t))
        }
        var p = Path(start: a, segments: [seg])
        p.isClosed = false
        var bestT = 0.0, bestD = Double.infinity
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let d = point(p, segment: 0, t: t).distance(to: q)
            if d < bestD { bestD = d; bestT = t }
        }
        // Refine by ternary search around the best sample.
        var lo = max(0, bestT - 1.0 / Double(samples)), hi = min(1, bestT + 1.0 / Double(samples))
        for _ in 0..<40 {
            let m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3
            if point(p, segment: 0, t: m1).distance(to: q) < point(p, segment: 0, t: m2).distance(to: q) { hi = m2 } else { lo = m1 }
        }
        let t = (lo + hi) / 2
        return (t, point(p, segment: 0, t: t).distance(to: q))
    }

    static func splitCubic(_ p0: Vec2, _ p1: Vec2, _ p2: Vec2, _ p3: Vec2, _ t: Double) -> (PathSegment, PathSegment) {
        let a = p0.lerp(to: p1, t), b = p1.lerp(to: p2, t), c = p2.lerp(to: p3, t)
        let d = a.lerp(to: b, t), e = b.lerp(to: c, t)
        let m = d.lerp(to: e, t)
        return (.cubic(to: m, control1: a, control2: d), .cubic(to: p3, control1: e, control2: c))
    }

    static func withEnd(_ s: PathSegment, _ e: Vec2) -> PathSegment {
        switch s {
        case .line: return .line(to: e)
        case .arc(_, let c, let cw): return .arc(to: e, center: c, clockwise: cw)
        case .cubic(_, let c1, let c2): return .cubic(to: e, control1: c1, control2: c2)
        }
    }

    private static func moveHandleRaw(_ p: Path, _ k: Int, _ h: Handle, _ v: Vec2) -> Path {
        moveHandle(p, k, h, to: v, keepSmooth: false)
    }
}
