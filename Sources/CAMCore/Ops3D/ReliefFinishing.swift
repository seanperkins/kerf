import CADCore
import Foundation

/// Raster finishing: parallel lines across the region, each sampled with the drop-cutter so the
/// tool (flat, ball or V) touches but never dips below the heightmap, then thinned within
/// `tolerance`. Adjacent lines are linked along the surface; other jumps retract to safe Z.
enum ReliefFinishing {
    static func moves(map: ReliefHeightmap, region: [[Vec2]], tool: Tool, stepover: Double, angle: Double,
                      coords: MachineCoordinates, tolerance: Double, clearance: Double) -> [Move] {
        let cutter = DropCutter(map: map, cutter: CutterProfile(tool: tool))
        let step = max(min(map.cellSize, stepover), 1e-6)
        let pattern = RasterPattern(region: region, angleDegrees: angle, spacing: stepover)
        var writer = PathWriter3D(coords: coords, feedRate: tool.feedRate, plungeRate: tool.plungeRate,
                                  clearance: clearance)
        let linkLimit = 2.5 * stepover
        var lastEnd: Vec2?
        for seg in pattern.zigzag {
            let samples = Polyline3D.sample(from: seg.start, to: seg.end, step: step)
            var pts = samples.map { Vec3($0, z: cutter.depth(at: $0)) }
            if let e = lastEnd, e.distance(to: seg.start) <= linkLimit, !writer.isAtSafeZ {
                // Surface-following link to the next line (drop-cutter keeps it gouge-free).
                // The link starts at the current position, which `dropFirst` below skips.
                let link = Polyline3D.sample(from: e, to: seg.start, step: step)
                pts = link.map { Vec3($0, z: cutter.depth(at: $0)) } + pts.dropFirst()
            } else {
                writer.enter(at: pts[0].xy, depth: pts[0].z)
            }
            writer.cut(through: Polyline3D.simplify(pts, tolerance: tolerance).dropFirst().map { $0 })
            lastEnd = seg.end
        }
        return writer.finish()
    }
}
