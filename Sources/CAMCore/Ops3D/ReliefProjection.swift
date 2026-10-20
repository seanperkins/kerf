import CADCore
import Foundation

/// Drops finished 2D toolpaths (profile, V-carve, texture, fluting…) onto a 3D model's surface.
///
/// Each cutting move is linearised (arcs too), subdivided to the heightmap cell size and every
/// point's depth becomes `surface + depth`, where `surface` is the drop-cutter depth of the
/// toolpath's own tool at that XY (so a depth of 0 just touches the model without gouging it, and
/// deeper cuts follow the surface). Outside the model's triangles the surface is the model's
/// bottom plane, as for 3D relief toolpaths. Points are then thinned within the document
/// tolerance. Rapids that change XY are left alone (they are at safe Z); vertical rapids that go
/// below the material top stop at the top instead, because the material they relied on being
/// cleared is now somewhere else — the following feed move covers the rest.
public enum ReliefProjection {
    public static func project(_ toolpaths: [Toolpath], ontoModel id: UUID, in context: CAMContext,
                               resolution: Double? = nil) throws -> [Toolpath] {
        guard let model = context.document.model(id: id) else { throw CAMError.missingModel(id) }
        guard model.mesh.triangleCount > 0 else { throw CAMError.noGeometry }
        let res = resolution ?? (context.units == .inch ? 0.01 : 0.25)
        return try toolpaths.map { try project($0, model: model, context: context, resolution: res) }
    }

    private enum Step {
        case rapid(Vec2, Double)
        case feed(Vec2, Double, feed: Double)
        case dwell(Double)
    }

    static func project(_ tp: Toolpath, model: PlacedModel, context: CAMContext, resolution: Double) throws -> Toolpath {
        let coords = context.coords
        let tol = context.tolerance
        // 1. Material-frame steps with arcs linearised.
        var steps: [Step] = []
        var pos: (xy: Vec2, depth: Double)?
        for m in tp.moves {
            switch m {
            case .dwell(let s): steps.append(.dwell(s))
            case .rapid(let t):
                let p = coords.material(fromMachine: t)
                steps.append(.rapid(p.xy, p.depth)); pos = p
            case .linear(let t, let f):
                let p = coords.material(fromMachine: t)
                steps.append(.feed(p.xy, p.depth, feed: f)); pos = p
            case .arcCW(let t, let c, let f), .arcCCW(let t, let c, let f):
                let p = coords.material(fromMachine: t)
                let centre = coords.materialXY(fromMachine: c)
                var clockwise = false
                if case .arcCW = m { clockwise = true }
                if let from = pos {
                    for q in arcPoints(from: from, to: p, centre: centre, clockwise: clockwise, tolerance: tol) {
                        steps.append(.feed(q.xy, q.depth, feed: f))
                    }
                } else {
                    steps.append(.feed(p.xy, p.depth, feed: f))
                }
                pos = p
            }
        }
        // 2. Heightmap over the cut area.
        var bounds = Rect2.empty
        for s in steps { if case .feed(let xy, _, _) = s { bounds.include(xy) } }
        guard !bounds.isEmpty else { return tp }
        let area = bounds.insetBy(-(tp.tool.radius + 2 * resolution))
        let cell = Relief3DOperation.cellSize(requested: resolution, area: area)
        let map = try ReliefHeightmap.rasterize(model, over: area, cellSize: cell)
        let cutter = DropCutter(map: map, cutter: CutterProfile(tool: tp.tool))
        let step = max(min(cell, 0.5 * max(tp.tool.radius, cell)), 1e-6)

        // 3. Re-emit with projected depths.
        var moves: [Move] = []
        var current: (xy: Vec2, depth: Double)?   // projected position
        var original: (xy: Vec2, depth: Double)?  // unprojected position (for interpolation)
        var run: [Vec3] = []
        var runFeed = 0.0
        func flush() {
            guard run.count > 1 else { run = []; return }
            for q in Polyline3D.simplify(run, tolerance: tol).dropFirst() {
                moves.append(.linear(to: coords.machine(q.xy, depth: q.z), feed: runFeed))
            }
            run = []
        }
        for s in steps {
            switch s {
            case .dwell(let secs):
                flush(); moves.append(.dwell(seconds: secs))
            case .rapid(let xy, let d):
                flush()
                let moved = current.map { !$0.xy.isApproximatelyEqual(to: xy, tolerance: 1e-9) } ?? true
                let depth = moved ? d : min(d, 0)
                moves.append(.rapid(to: coords.machine(xy, depth: depth)))
                current = (xy, depth); original = (xy, d)
            case .feed(let xy, let d, let f):
                guard let from = original, let start = current else {
                    let q = Vec3(xy, z: cutter.depth(at: xy) + d)
                    moves.append(.linear(to: coords.machine(q.xy, depth: q.z), feed: f))
                    current = (q.xy, q.z); original = (xy, d)
                    continue
                }
                if run.isEmpty || abs(runFeed - f) > 1e-12 {
                    flush(); run = [Vec3(start.xy, z: start.depth)]; runFeed = f
                }
                let n = max(1, Int(ceil(from.xy.distance(to: xy) / step)))
                for k in 1...n {
                    let t = Double(k) / Double(n)
                    let p = from.xy.lerp(to: xy, t)
                    run.append(Vec3(p, z: cutter.depth(at: p) + from.depth + (d - from.depth) * t))
                }
                current = (xy, run[run.count - 1].z); original = (xy, d)
            }
        }
        flush()
        var out = tp
        out.moves = moves
        out.metadata["projected"] = model.name
        return out
    }

    /// Points along an arc (excluding the start, including the end), Z interpolated linearly.
    static func arcPoints(from a: (xy: Vec2, depth: Double), to b: (xy: Vec2, depth: Double), centre c: Vec2,
                          clockwise: Bool, tolerance: Double) -> [(xy: Vec2, depth: Double)] {
        let r = a.xy.distance(to: c)
        guard r > 1e-9 else { return [b] }
        let a0 = atan2(a.xy.y - c.y, a.xy.x - c.x)
        var a1 = atan2(b.xy.y - c.y, b.xy.x - c.x)
        if clockwise {
            while a1 >= a0 - 1e-12 { a1 -= 2 * .pi }
        } else {
            while a1 <= a0 + 1e-12 { a1 += 2 * .pi }
        }
        let sweep = a1 - a0
        let maxStep = 2 * acos(max(-1, min(1, 1 - min(tolerance, r) / r)))
        let n = max(1, Int(ceil(abs(sweep) / max(maxStep, 1e-3))))
        var out: [(xy: Vec2, depth: Double)] = []
        for k in 1...n {
            let t = Double(k) / Double(n)
            if k == n { out.append(b); break }
            let ang = a0 + sweep * t
            out.append((Vec2(c.x + r * cos(ang), c.y + r * sin(ang)), a.depth + (b.depth - a.depth) * t))
        }
        return out
    }
}
