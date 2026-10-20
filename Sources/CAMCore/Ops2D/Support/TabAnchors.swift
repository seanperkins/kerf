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

    /// Tab centre parameters for each closed loop: every anchor goes to the loop nearest to its
    /// position, at that loop's closest parameter. Anchors on missing vectors are ignored.
    public static func centers(for anchors: [TabAnchor], loops: [ArcLengthChain], document: Document,
                               tolerance: Double) -> [[Double]] {
        var out = Array(repeating: [Double](), count: loops.count)
        for a in anchors {
            guard let p = point(of: a, in: document, tolerance: tolerance) else { continue }
            var best: (index: Int, s: Double, d: Double)?
            for (i, loop) in loops.enumerated() where loop.isClosed && loop.length > 0 {
                let pr = loop.project(p)
                if pr.distance < (best?.d ?? .infinity) { best = (i, pr.s, pr.distance) }
            }
            if let b = best { out[b.index].append(b.s) }
        }
        return out.map { $0.sorted() }
    }
}
