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

    /// What a manual anchor is judged against. `outline` is the anchor's part as drawn (its vector
    /// and whatever selected vectors the offset joins it to, as the even-odd region the toolpath
    /// offsets), `part` what the toolpath cuts for it (the outline offset by `offset`), and `cut`
    /// whether this pass cuts the anchor's vector at all: its part has a loop that leaves something to
    /// hold (not a sliver narrower than the tool) and the vector's own offset survives (a hole smaller
    /// than this pass's offset is not cut by it).
    public struct OwnLoops {
        public var outline: [ArcLengthChain]
        public var part: [ArcLengthChain]
        public var offset: Double
        public var cut: Bool
        public init(outline: [ArcLengthChain], part: [ArcLengthChain], offset: Double, cut: Bool) {
            self.outline = outline; self.part = part; self.offset = offset; self.cut = cut
        }
    }

    /// Tab centre parameters for each closed loop. An anchor travels with its vector, so it is used
    /// only when that vector is a closed path of a shape in `shapeIDs` (the shapes this toolpath
    /// cuts), the anchor lies on its part's outline (`ownLoops`; an edge two vectors share is inside
    /// the part), the part's loop runs nearest it at a point one offset from the anchor's own vector
    /// and standing straight across from the stretch the anchor is on (`standsAcross`: straight across
    /// from the anchor itself, or further along that stretch where a corner trims it, within the miter
    /// limit's reach, never across a corner of the vector or from another stretch), and one of `loops`
    /// runs through that point; it goes onto that loop there. One
    /// on another part however near, on an open vector, on a vector that no longer exists, on a
    /// stretch the toolpath does not cut, or whose own loop the offset swallowed (a hole smaller than
    /// the tool, in a part whose other loops survive) is never attached to whatever loop happens to
    /// be nearest; the result says which anchors were placed, so the operation can say so.
    public static func centers(for anchors: [TabAnchor], loops: [ArcLengthChain], shapeIDs: Set<UUID>,
                               ownLoops: (TabAnchor) -> OwnLoops, document: Document,
                               tolerance: Double) -> Resolution {
        var out = Array(repeating: [Double](), count: loops.count)
        var placed = Array(repeating: false, count: anchors.count), cut = placed
        var own: [UUID: [Int: OwnLoops]] = [:]
        for (n, a) in anchors.enumerated() {
            guard shapeIDs.contains(a.shapeID), let shape = document.shape(id: a.shapeID),
                  shape.paths.indices.contains(a.pathIndex), shape.paths[a.pathIndex].isClosed,
                  let vector = chain(for: a, in: document, tolerance: tolerance) else { continue }
            let p = vector.point(at: min(max(a.fraction, 0), 1) * vector.length)
            // Where the tab would sit on the part's own loop, then the toolpath loop through there.
            let mine = own[a.shapeID]?[a.pathIndex] ?? {
                let l = ownLoops(a)
                own[a.shapeID, default: [:]][a.pathIndex] = l
                return l
            }()
            cut[n] = mine.cut
            let slack = 8 * tolerance + 1e-6
            guard (nearest(p, on: mine.outline)?.distance ?? .infinity) <= slack,
                  let site = nearest(p, on: mine.part), site.distance <= ProfileGeometry.sharpMiterLimit * mine.offset + slack,
                  abs(vector.project(site.point).distance - mine.offset) <= slack,
                  standsAcross(from: p, at: site.point, on: vector, offset: mine.offset, slack: slack) else { continue }
            var best: (index: Int, s: Double, d: Double)?
            for (i, loop) in loops.enumerated() where loop.isClosed && loop.length > 0 {
                let pr = loop.project(site.point)
                if pr.distance <= slack, pr.distance < (best?.d ?? .infinity) { best = (i, pr.s, pr.distance) }
            }
            if let b = best {
                out[b.index].append(b.s)
                placed[n] = true
            }
        }
        return Resolution(centers: out.map { $0.sorted() }, placed: placed, cut: cut)
    }

    /// What became of each anchor on one pass: `centers` per loop, and per anchor whether it was
    /// `placed` and whether its vector was `cut` on this pass at all (false for a vector that is gone,
    /// not selected, open, or whose loop this pass's offset swallowed).
    public struct Resolution {
        public var centers: [[Double]]
        public var placed: [Bool]
        public var cut: [Bool]
        /// Anchors that got no tab.
        public var ignored: Int { placed.filter { !$0 }.count }
    }

    /// Whether the point `site` of the part's loop is the anchor's own: some point of the vector (a foot)
    /// stands `offset` from it, and the anchor is that foot or lies along the line the site's offset
    /// stands square to. Two stretches of a vector can each have a foot at `offset` from one point (the
    /// inside of a corner), so every stretch is tried. A foot beyond a corner of the vector is not: the
    /// site there is straight across from the next stretch, and where two merged loops swallow the
    /// anchor's own stretch it would carry the tab round the corner (issue #52). A little lean is allowed
    /// (the vector's flattened curves turn a few degrees from one chord to the next).
    private static func standsAcross(from anchor: Vec2, at site: Vec2, on vector: ArcLengthChain, offset: Double,
                                     slack: Double) -> Bool {
        let lean = max(slack, 0.3 * offset)
        for (a, b) in zip(vector.walk, vector.walk.dropFirst()) {
            let foot = Polygon2D.closestPoint(onSegment: a, b, to: site).0
            guard abs(foot.distance(to: site) - offset) <= slack else { continue }
            let back = anchor - foot
            if back.length <= slack || abs((site - foot).dot(back / back.length)) <= lean { return true }
        }
        return false
    }

    private static func nearest(_ p: Vec2, on loops: [ArcLengthChain]) -> (point: Vec2, distance: Double)? {
        var best: (point: Vec2, distance: Double)?
        for l in loops where l.isClosed && l.length > 0 {
            let pr = l.project(p)
            if pr.distance < (best?.distance ?? .infinity) { best = (l.point(at: pr.s), pr.distance) }
        }
        return best
    }
}
