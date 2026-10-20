import CADCore
import Foundation

/// Cutting order honouring the selected vectors: optionally machine them in selection order,
/// and optionally start loops (and engraved lines) at each vector's start point.
struct VCarveOrdering {
    /// One selected vector (shape), in selection order.
    struct Group {
        /// Even-odd region of the shape's closed paths (may be empty).
        var region: VCarveRegion
        /// The shape's open paths, flattened (for engraving strokes).
        var lines: [[Vec2]]
        /// Start point of the shape's first path.
        var start: Vec2
    }

    var groups: [Group]
    var useStartPoints: Bool
    var useSelectionOrder: Bool
    /// Distance within which a stroke counts as lying on an open vector.
    var lineTolerance: Double

    init(shapes: [Shape], useStartPoints: Bool, useSelectionOrder: Bool, tolerance: Double, units: LengthUnit) {
        groups = shapes.compactMap { shape in
            guard let first = shape.paths.first else { return nil }
            return Group(region: VCarveRegion(paths: shape.paths.filter(\.isClosed), tolerance: tolerance, units: units),
                         lines: shape.paths.filter { !$0.isClosed }.map { $0.flattened(tolerance: tolerance) },
                         start: first.start)
        }
        self.useStartPoints = useStartPoints
        self.useSelectionOrder = useSelectionOrder
        lineTolerance = max(tolerance * 4, units == .inch ? 0.001 : 0.025)
    }

    /// Index of the first group (selection order) the stroke belongs to, or nil.
    func group(of stroke: VCarveStroke) -> Int? {
        guard !stroke.points.isEmpty else { return nil }
        let probe = stroke.points[stroke.points.count / 2].xy
        let ends = [stroke.points[0].xy, stroke.points[stroke.points.count - 1].xy, probe]
        for (i, g) in groups.enumerated() {
            if g.lines.contains(where: { line in ends.allSatisfy { Self.distance($0, to: line) <= lineTolerance } }) {
                return i
            }
        }
        for (i, g) in groups.enumerated() where !g.region.isEmpty && g.region.contains(probe) { return i }
        return nil
    }

    func order(_ strokes: [VCarveStroke]) -> [VCarveStroke] {
        let tagged = strokes.map { s -> (stroke: VCarveStroke, group: Int?) in
            let g = group(of: s)
            guard useStartPoints, let g else { return (s, g) }
            return (Self.startingNear(s, groups[g].start), g)
        }
        guard useSelectionOrder else {
            return VCarveStrokes.ordered(tagged.map(\.stroke))
        }
        var out: [VCarveStroke] = []
        var cursor = Vec2.zero
        for i in 0...groups.count {
            let part = tagged.filter { ($0.group ?? groups.count) == i }.map(\.stroke)
            guard !part.isEmpty else { continue }
            let from = useStartPoints && i < groups.count ? groups[i].start : cursor
            let ordered = VCarveStrokes.ordered(part, from: from)
            out += ordered
            if let last = ordered.last?.points.last { cursor = last.xy }
        }
        return out
    }

    /// A closed loop rotated to begin at its point nearest `p`; an open stroke whose start is
    /// the vector's start is pinned to that direction.
    static func startingNear(_ s: VCarveStroke, _ p: Vec2) -> VCarveStroke {
        var out = s
        if s.isClosed {
            let pts = Array(s.points.dropLast())   // drop the repeated closing point
            guard pts.count >= 3,
                  let k = pts.indices.min(by: { pts[$0].xy.distance(to: p) < pts[$1].xy.distance(to: p) }) else { return s }
            let rotated = Array(pts[k...] + pts[..<k])
            out.points = rotated + [rotated[0]]
        } else if s.points[0].xy.distance(to: p) < 1e-6 {
            out.fixedDirection = true
        }
        return out
    }

    static func distance(_ p: Vec2, to line: [Vec2]) -> Double {
        guard line.count >= 2 else { return line.first.map { $0.distance(to: p) } ?? .infinity }
        var best = Double.infinity
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i]
            let ab = b - a
            let len2 = ab.dot(ab)
            let t = len2 > 0 ? max(0, min(1, (p - a).dot(ab) / len2)) : 0
            best = min(best, (a + ab * t).distance(to: p))
        }
        return best
    }
}
