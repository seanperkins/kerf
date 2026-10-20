import CADCore
import Foundation

/// Z-level roughing with a flat end mill. At each level the tool centre may go wherever a flat
/// cutter of radius `R + allowance`, lifted by `allowance`, stays above the model — so at least
/// `allowance` is left on the model both sideways and vertically. That tool-centre region is
/// contoured from a grid of flat-cutter drop depths and cleared like a 2D pocket: offset
/// (contour-parallel, inside-out) or raster with an optional profile pass around the region.
/// Levels are nested, so rapid descents stop just above the previous level instead of at the
/// material top, and links between passes stay inside the level's region.
enum ReliefRoughing {
    static func moves(map: ReliefHeightmap, region: [[Vec2]], tool: Tool, allowance: Double, passDepth: Double?,
                      strategy: PocketStrategy, coords: MachineCoordinates, clearance: Double,
                      tolerance: Double) throws -> [Move] {
        let levels = ReliefLevelRegions(map: map, toolRadius: tool.radius, allowance: allowance, boundary: region,
                                        tolerance: tolerance)
        let stepover = min(max(tool.stepover, 1e-4), tool.diameter * 0.9)
        let deepest = levels.deepestFloor
        guard deepest > 1e-9 else { return [] }
        let settings = DepthSettings(startDepth: 0, cutDepth: deepest, passDepth: passDepth)
        try settings.validatePassDepth(toolStepdown: tool.stepdown)
        let depths = settings.passDepths(toolStepdown: tool.stepdown)

        var writer = PathWriter3D(coords: coords, feedRate: tool.feedRate, plungeRate: tool.plungeRate,
                                  clearance: clearance)
        var previous = 0.0
        var here = coords.materialXY(fromMachine: coords.job.home)
        for level in depths {
            let centres = levels.region(at: level)
            guard !centres.isEmpty else { continue }
            let planner = PocketPlanner(region: centres, toolRadius: 0, stepover: stepover, allowance: 0,
                                        tolerance: tolerance, direction: .climb)
            let groups: [[Chain2D]]
            switch strategy {
            case .offset: groups = planner.offsetClearing(from: here)
            case .raster(let angle, let profilePass):
                groups = planner.rasterClearing(angle: angle, profilePass: profilePass, from: here)
            }
            let linker = RegionLinker(region: centres, maxLength: 2 * tool.diameter, tolerance: tolerance)
            for chains in groups {
                for chain in chains where !chain.points.isEmpty {
                    if let cur = writer.position, !writer.isAtSafeZ, abs(cur.depth - level) < 1e-9,
                       let link = linker.link(from: cur.xy, to: chain.start) {
                        for p in link { writer.cut(to: p, depth: level) }
                    } else {
                        writer.enter(at: chain.start, depth: level, approachDepth: previous - clearance)
                    }
                    for p in chain.points.dropFirst() { writer.cut(to: p, depth: level) }
                    if chain.isClosed { writer.cut(to: chain.start, depth: level) }
                    here = chain.end
                }
            }
            writer.retract()
            previous = level
        }
        return writer.finish()
    }
}
