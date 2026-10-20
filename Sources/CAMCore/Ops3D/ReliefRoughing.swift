import CADCore
import Foundation

/// Z-level roughing with a flat end mill. At each level the tool centre may go wherever a flat
/// cutter of radius `R + allowance`, lifted by `allowance`, stays above the model — so at least
/// `allowance` is left on the model both sideways and vertically. Each level is raster cleared
/// (runs of allowed samples along the raster lines); levels are nested, so rapid descents stop
/// just above the previous level instead of at the material top.
enum ReliefRoughing {
    static func moves(map: ReliefHeightmap, region: [[Vec2]], tool: Tool, allowance: Double, passDepth: Double?,
                      angle: Double, coords: MachineCoordinates, clearance: Double) -> [Move] {
        let a = max(0, allowance)
        let fat = DropCutter(map: map, cutter: CutterProfile(shape: .flat, radius: tool.radius + a))
        let stepover = min(max(tool.stepover, 1e-4), tool.diameter * 0.9)
        let step = max(min(map.cellSize, stepover / 2), 1e-6)
        let pattern = RasterPattern(region: region, angleDegrees: angle, spacing: stepover)

        // Sample every raster segment once; the floor is the deepest the tool centre may go.
        struct Line { var points: [Vec2]; var floors: [Double] }
        let lines: [Line] = pattern.zigzag.map { seg in
            let pts = Polyline3D.sample(from: seg.start, to: seg.end, step: step)
            return Line(points: pts, floors: pts.map { fat.depth(at: $0) - a })
        }
        let deepest = lines.flatMap(\.floors).max() ?? 0
        guard deepest > 1e-9 else { return [] }
        let levels = DepthSettings(startDepth: 0, cutDepth: deepest, passDepth: passDepth)
            .passDepths(toolStepdown: tool.stepdown)

        var writer = PathWriter3D(coords: coords, feedRate: tool.feedRate, plungeRate: tool.plungeRate,
                                  clearance: clearance)
        var previous = 0.0
        for level in levels {
            var last: (line: Int, end: Vec2)?
            for (li, line) in lines.enumerated() {
                for run in runs(line.floors, level: level) {
                    let start = line.points[run.lowerBound], end = line.points[run.upperBound]
                    if let l = last, li - l.line <= 1, !writer.isAtSafeZ,
                       linkIsClear(from: l.end, to: start, level: level, cutter: fat, allowance: a, step: step) {
                        writer.cut(to: start, depth: level)
                    } else {
                        writer.enter(at: start, depth: level, approachDepth: previous - clearance)
                    }
                    writer.cut(to: end, depth: level)
                    last = (li, end)
                }
            }
            writer.retract()
            previous = level
        }
        return writer.finish()
    }

    /// Index ranges of consecutive samples whose floor is at or below `level`.
    static func runs(_ floors: [Double], level: Double) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var start: Int?
        for (k, f) in floors.enumerated() {
            if f >= level - 1e-9 {
                if start == nil { start = k }
            } else if let s = start {
                out.append(s...(k - 1)); start = nil
            }
        }
        if let s = start { out.append(s...(floors.count - 1)) }
        return out
    }

    private static func linkIsClear(from a: Vec2, to b: Vec2, level: Double, cutter: DropCutter, allowance: Double,
                                    step: Double) -> Bool {
        Polyline3D.sample(from: a, to: b, step: step).allSatisfy { cutter.depth(at: $0) - allowance >= level - 1e-9 }
    }
}
