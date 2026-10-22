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
    /// offset to the vector it came from and runs exactly that far along every untrimmed stretch,
    /// so its nearest vertex is one offset away. A loop that two vectors merged into is the offset
    /// of each; a loop of some other vector, or one the offset swallowed, is not.
    public static func isOffset(_ loop: ArcLengthChain, of source: ArcLengthChain, by offset: Double, tolerance: Double) -> Bool {
        var nearest = Double.infinity
        for v in loop.chain.points { nearest = min(nearest, source.project(v).distance) }
        return abs(nearest - offset) <= 4 * tolerance + 1e-6
    }

    /// Tab centre parameters for each closed loop. An anchor travels with its vector, so it is used
    /// only when that vector is a closed path of a shape in `shapeIDs` (the shapes this toolpath
    /// cuts) and one of `loops` is that vector offset by `offset` (what the toolpath applied); it
    /// goes onto that loop at the parameter nearest its position. One on another part however
    /// near, on an open vector, on a vector that no longer exists, or whose own loop the offset
    /// swallowed is never attached to whatever loop happens to be nearest; `ignored` counts them so
    /// the operation can say so.
    public static func centers(for anchors: [TabAnchor], loops: [ArcLengthChain], shapeIDs: Set<UUID>,
                               offset: Double, document: Document, tolerance: Double) -> (centers: [[Double]], ignored: Int) {
        var out = Array(repeating: [Double](), count: loops.count)
        var ignored = 0
        for a in anchors {
            guard shapeIDs.contains(a.shapeID), let shape = document.shape(id: a.shapeID),
                  shape.paths.indices.contains(a.pathIndex), shape.paths[a.pathIndex].isClosed,
                  let own = chain(for: a, in: document, tolerance: tolerance) else {
                ignored += 1
                continue
            }
            let p = own.point(at: min(max(a.fraction, 0), 1) * own.length)
            var best: (index: Int, s: Double, d: Double)?
            for (i, loop) in loops.enumerated()
            where loop.isClosed && loop.length > 0 && isOffset(loop, of: own, by: offset, tolerance: tolerance) {
                let pr = loop.project(p)
                if pr.distance < (best?.d ?? .infinity) { best = (i, pr.s, pr.distance) }
            }
            if let b = best { out[b.index].append(b.s) } else { ignored += 1 }
        }
        return (out.map { $0.sorted() }, ignored)
    }
}
