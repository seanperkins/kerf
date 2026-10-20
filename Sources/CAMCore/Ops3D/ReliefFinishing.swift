import CADCore
import Foundation

/// 3D finishing. Every pattern is planned in 2D inside the region, then each point is dropped
/// onto the heightmap with the drop-cutter so the tool (flat, ball or V) touches but never dips
/// below it, and the result is thinned within `tolerance`. Nearby passes are linked along the
/// surface (the drop-cutter keeps links gouge-free); other jumps retract to safe Z.
enum ReliefFinishing {
    /// Raster: parallel lines across the region at `angle`, zig-zag linked.
    static func moves(map: ReliefHeightmap, region: [[Vec2]], tool: Tool, stepover: Double, angle: Double,
                      coords: MachineCoordinates, tolerance: Double, clearance: Double) -> [Move] {
        let pattern = RasterPattern(region: region, angleDegrees: angle, spacing: stepover)
        let lines = pattern.zigzag.map { [$0.start, $0.end] }
        return emit(lines, map: map, tool: tool, stepover: stepover, coords: coords, tolerance: tolerance,
                    clearance: clearance)
    }

    /// Offset: contour-parallel rings from the region boundary inwards; with `spiral`, each run of
    /// singly nested rings is blended into one continuous spiral.
    static func offsetMoves(map: ReliefHeightmap, region: [[Vec2]], tool: Tool, stepover: Double, spiral: Bool,
                            coords: MachineCoordinates, tolerance: Double, clearance: Double) -> [Move] {
        let boundary = Polygon2D.region(fromLoops: region)
        let planner = PocketPlanner(region: boundary, toolRadius: 0, stepover: stepover, allowance: 0,
                                    tolerance: tolerance, direction: .climb)
        let levels = planner.offsetLevels()
        var polylines: [[Vec2]] = []
        var here = coords.materialXY(fromMachine: coords.job.home)
        var k = 0
        while k < levels.count {
            // A spiral needs one ring per level; it runs until the area splits or ends.
            if spiral, levels[k].count == 1 {
                var run = [levels[k][0]]
                var n = k + 1
                while n < levels.count, levels[n].count == 1 { run.append(levels[n][0]); n += 1 }
                let path = spiralPath(run, from: here, step: map.cellSize, tolerance: tolerance)
                polylines.append(path)
                here = path.last ?? here
                k = n
                continue
            }
            var remaining = levels[k]
            while !remaining.isEmpty {
                let i = remaining.indices.min { Polygon2D.distance(from: here, toLoop: remaining[$0])
                    < Polygon2D.distance(from: here, toLoop: remaining[$1]) }!
                let loop = Polygon2D.rotatedLoop(remaining.remove(at: i), nearestTo: here, tolerance: tolerance)
                polylines.append(loop + [loop[0]])
                here = loop[0]
            }
            k += 1
        }
        return emit(polylines, map: map, tool: tool, stepover: stepover, coords: coords, tolerance: tolerance,
                    clearance: clearance)
    }

    /// Blends consecutive rings (outermost first): while going once around ring k the path moves
    /// steadily onto ring k+1, then finishes with a full lap of the innermost ring.
    static func spiralPath(_ rings: [[Vec2]], from start: Vec2, step: Double, tolerance: Double) -> [Vec2] {
        guard var current = rings.first.map({ Polygon2D.rotatedLoop($0, nearestTo: start, tolerance: tolerance) })
        else { return [] }
        var out: [Vec2] = []
        for next in rings.dropFirst() {
            let a = ArcLengthChain(Chain2D(points: current, isClosed: true))
            let rotated = Polygon2D.rotatedLoop(next, nearestTo: current[0], tolerance: tolerance)
            let b = ArcLengthChain(Chain2D(points: rotated, isClosed: true))
            let n = max(8, Int(ceil(a.length / max(step, 1e-6))))
            for i in 0..<n {
                let t = Double(i) / Double(n)
                out.append(a.point(at: t * a.length).lerp(to: b.point(at: t * b.length), t))
            }
            current = rotated
        }
        out += current + [current[0]]
        return out
    }

    /// Cuts each polyline in order: densified to the heightmap cell size, dropped onto the
    /// surface, simplified. Polylines starting close to the previous end are linked on the surface.
    private static func emit(_ polylines: [[Vec2]], map: ReliefHeightmap, tool: Tool, stepover: Double,
                             coords: MachineCoordinates, tolerance: Double, clearance: Double) -> [Move] {
        let cutter = DropCutter(map: map, cutter: CutterProfile(tool: tool))
        let step = max(min(map.cellSize, stepover), 1e-6)
        var writer = PathWriter3D(coords: coords, feedRate: tool.feedRate, plungeRate: tool.plungeRate,
                                  clearance: clearance)
        let linkLimit = 2.5 * stepover
        var lastEnd: Vec2?
        for line in polylines where line.count >= 2 {
            var samples: [Vec2] = [line[0]]
            for i in 1..<line.count {
                samples += Polyline3D.sample(from: line[i - 1], to: line[i], step: step).dropFirst()
            }
            var pts = samples.map { Vec3($0, z: cutter.depth(at: $0)) }
            if let e = lastEnd, e.distance(to: line[0]) <= linkLimit, !writer.isAtSafeZ {
                // Surface-following link; it starts at the current position, which `dropFirst`
                // below skips.
                let link = Polyline3D.sample(from: e, to: line[0], step: step)
                pts = link.map { Vec3($0, z: cutter.depth(at: $0)) } + pts.dropFirst()
            } else {
                writer.enter(at: pts[0].xy, depth: pts[0].z)
            }
            writer.cut(through: Polyline3D.simplify(pts, tolerance: tolerance).dropFirst().map { $0 })
            lastEnd = line[line.count - 1]
        }
        return writer.finish()
    }
}
