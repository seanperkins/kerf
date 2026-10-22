import CADCore
import Foundation

/// Converts between user-placed `TabAnchor`s and positions (material XY), and distributes
/// anchors onto profile toolpath loops.
public enum TabAnchors {
    /// Arc-length parameterisation of one path of a shape (nil for a missing shape/path).
    public static func chain(for anchor: TabAnchor, in document: Document, tolerance: Double) -> ArcLengthChain? {
        guard let shape = document.shape(id: anchor.shapeID), shape.paths.indices.contains(anchor.pathIndex) else {
            return nil
        }
        return chain(shape.paths[anchor.pathIndex], tolerance: tolerance)
    }

    public static func chain(_ path: Path, tolerance: Double) -> ArcLengthChain? {
        let pts = path.flattened(tolerance: tolerance)
        guard pts.count > 1 else { return nil }
        let alc = ArcLengthChain(Chain2D(points: pts, isClosed: path.isClosed))
        return alc.length > 0 ? alc : nil
    }

    /// Material XY of an anchor (nil when its vector no longer exists).
    public static func point(of anchor: TabAnchor, in document: Document, tolerance: Double) -> Vec2? {
        guard let alc = chain(for: anchor, in: document, tolerance: tolerance) else { return nil }
        return alc.point(at: min(max(anchor.fraction, 0), 1) * alc.length)
    }

    /// The anchor on `shapes` closest to `p`, if within `maxDistance` of a path.
    public static func anchor(nearest p: Vec2, on shapes: [Shape], maxDistance: Double,
                              tolerance: Double) -> TabAnchor? {
        var best: (anchor: TabAnchor, distance: Double)?
        for s in shapes {
            for (i, path) in s.paths.enumerated() {
                guard let alc = chain(path, tolerance: tolerance) else { continue }
                let pr = alc.project(p)
                guard pr.distance <= maxDistance, pr.distance < (best?.distance ?? .infinity) else { continue }
                var f = pr.s / alc.length
                if f >= 1 { f = alc.isClosed ? 0 : 1 }
                best = (TabAnchor(shapeID: s.id, pathIndex: i, fraction: f), pr.distance)
            }
        }
        return best?.anchor
    }

    /// True when `loop` is `source` offset by `offset`: an offset loop is never nearer than its
    /// offset to the curve it came from and runs exactly that far along every untrimmed stretch,
    /// so the nearest of its vertices and edge midpoints, or of the source's vertices to it, is
    /// one offset away (a mitered loop has only corner vertices, farther out; its edges and the
    /// source's corners are not). A loop of some other curve, or one the offset swallowed, fails;
    /// a loop two curves merged into is the offset of each.
    static func isOffset(_ loop: ArcLengthChain, of source: ArcLengthChain, by offset: Double, tolerance: Double) -> Bool {
        let slack = 4 * tolerance + 1e-6
        // Far apart: no need to walk either.
        let (lo, hi) = bounds(loop.chain.points), (so, sh) = bounds(source.chain.points)
        let grow = offset + slack
        guard hi.x >= so.x - grow, lo.x <= sh.x + grow, hi.y >= so.y - grow, lo.y <= sh.y + grow else { return false }
        var nearest = Double.infinity
        let walk = loop.chain.walk
        for (i, v) in walk.enumerated() {
            nearest = min(nearest, source.project(v).distance)
            if i + 1 < walk.count { nearest = min(nearest, source.project((v + walk[i + 1]) * 0.5).distance) }
        }
        for v in source.chain.points { nearest = min(nearest, loop.project(v).distance) }
        return abs(nearest - offset) <= slack
    }

    private static func bounds(_ pts: [Vec2]) -> (Vec2, Vec2) {
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        for p in pts {
            lo = Vec2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo, hi)
    }

    /// Tab centre parameters for each closed loop. An anchor travels with its vector, so it is used
    /// only when that vector is a closed path of a shape in `shapeIDs` (the shapes this toolpath
    /// cuts) and the loop the toolpath would cut for that shape alone (`ownLoops`, the same side,
    /// offset and join) runs through one of `loops` at the anchor's nearest point; it goes onto
    /// that loop there. One on another part however near, on an open vector, on a vector that no
    /// longer exists, or whose own loop the offset swallowed or merged away is never attached to
    /// whatever loop happens to be nearest; `ignored` counts them so the operation can say so.
    public static func centers(for anchors: [TabAnchor], loops: [ArcLengthChain], shapeIDs: Set<UUID>,
                               ownLoops: (Shape) -> [ArcLengthChain], document: Document,
                               tolerance: Double) -> (centers: [[Double]], ignored: Int) {
        var out = Array(repeating: [Double](), count: loops.count)
        var ignored = 0
        var own: [UUID: [ArcLengthChain]] = [:]
        for a in anchors {
            guard shapeIDs.contains(a.shapeID), let shape = document.shape(id: a.shapeID),
                  shape.paths.indices.contains(a.pathIndex), shape.paths[a.pathIndex].isClosed,
                  let vector = chain(for: a, in: document, tolerance: tolerance) else {
                ignored += 1
                continue
            }
            let p = vector.point(at: min(max(a.fraction, 0), 1) * vector.length)
            // Where the tab would sit on this shape's own loop, then the toolpath loop through there.
            if own[shape.id] == nil { own[shape.id] = ownLoops(shape) }
            var site: (point: Vec2, distance: Double)?
            for l in own[shape.id]! where l.isClosed && l.length > 0 {
                let pr = l.project(p)
                if pr.distance < (site?.distance ?? .infinity) { site = (l.point(at: pr.s), pr.distance) }
            }
            var best: (index: Int, s: Double, d: Double)?
            if let site {
                for (i, loop) in loops.enumerated() where loop.isClosed && loop.length > 0 {
                    let pr = loop.project(site.point)
                    if pr.distance <= 8 * tolerance + 1e-6, pr.distance < (best?.d ?? .infinity) { best = (i, pr.s, pr.distance) }
                }
            }
            if let b = best { out[b.index].append(b.s) } else { ignored += 1 }
        }
        return (out.map { $0.sorted() }, ignored)
    }
}
