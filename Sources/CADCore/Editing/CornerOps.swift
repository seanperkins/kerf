import Foundation

/// Fillets (round) and chamfers (bevel) on corners between two straight segments.
public enum CornerOps {
    public enum Kind: Hashable, Sendable {
        /// Tangent arc of this radius.
        case fillet(radius: Double)
        /// Straight cut starting this far from the corner along each edge.
        case chamfer(distance: Double)
    }

    /// Applies `kind` to the corners of `path`. `corners` holds vertex indices (vertex k is
    /// where segment k starts; closed paths get an explicit closing segment first, as in the
    /// node-editing form); nil = every line–line corner sharper than `maxAngle` degrees.
    /// Corners whose edges are too short are skipped.
    public static func apply(_ kind: Kind, to path: Path, corners: Set<Int>? = nil, maxAngle: Double = 179) -> Path {
        var segs = path.segments
        guard segs.count >= 2 else { return path }
        if path.isClosed, !segs.last!.end.isApproximatelyEqual(to: path.start, tolerance: 1e-9) {
            segs.append(.line(to: path.start))
        }
        let n = segs.count
        func vertex(_ k: Int) -> Vec2 { k == 0 ? path.start : segs[k - 1].end }
        func isLine(_ j: Int) -> Bool { if case .line = segs[j] { return true }; return false }
        func length(_ j: Int) -> Double { vertex(j).distance(to: path.isClosed ? vertex((j + 1) % n) : segs[j].end) }

        struct Cut { var a: Vec2; var b: Vec2; var seg: PathSegment; var trim: Double }
        var cuts = [Cut?](repeating: nil, count: n)
        let range = path.isClosed ? Array(0..<n) : Array(1..<n)
        for k in range where corners?.contains(k) ?? true {
            let jin = (k - 1 + n) % n, jout = k
            guard isLine(jin), isLine(jout) else { continue }
            let p = vertex(k)
            let lin = length(jin), lout = length(jout)
            guard lin > 1e-12, lout > 1e-12 else { continue }
            let f1 = (vertex(jin) - p) / lin
            let f2 = ((path.isClosed ? vertex((k + 1) % n) : segs[k].end) - p) / lout
            let theta = acos(max(-1, min(1, f1.dot(f2))))  // angle between the edges at the corner
            guard theta > 1e-6, theta * 180 / .pi <= maxAngle + 1e-9 else { continue }
            switch kind {
            case .fillet(let r):
                guard r > 0 else { continue }
                let d = r / tan(theta / 2)
                let a = p + f1 * d, b = p + f2 * d
                let c = p + (f1 + f2).normalized * (r / sin(theta / 2))
                let leftTurn = (-f1).cross(f2) > 0
                cuts[k] = Cut(a: a, b: b, seg: .arc(to: b, center: c, clockwise: !leftTurn), trim: d)
            case .chamfer(let d):
                guard d > 0 else { continue }
                let a = p + f1 * d, b = p + f2 * d
                cuts[k] = Cut(a: a, b: b, seg: .line(to: b), trim: d)
            }
        }
        // Drop corners that would overrun an edge.
        var changed = true
        while changed {
            changed = false
            for j in 0..<n {
                let next = (j + 1) % n
                let s = cuts[j]?.trim ?? 0
                let e = (path.isClosed || next != 0) ? (cuts[next]?.trim ?? 0) : 0
                if s + e > length(j) + 1e-9 {
                    if e >= s, cuts[next] != nil { cuts[next] = nil } else { cuts[j] = nil }
                    changed = true
                }
            }
        }
        guard cuts.contains(where: { $0 != nil }) else { return path }
        var out = Path(start: path.isClosed ? (cuts[0]?.b ?? path.start) : path.start, isClosed: path.isClosed)
        var cur = out.start
        for j in 0..<n {
            let next = (j + 1) % n
            if (path.isClosed || next != 0), let c = cuts[next] {
                if !c.a.isApproximatelyEqual(to: cur, tolerance: 1e-12) { out.segments.append(.line(to: c.a)) }
                out.segments.append(c.seg)
                cur = c.b
            } else {
                out.segments.append(segs[j])
                cur = segs[j].end
            }
        }
        return out
    }
}
