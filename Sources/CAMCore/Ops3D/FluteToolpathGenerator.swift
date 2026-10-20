import CADCore
import Foundation

/// Fluting toolpaths: the tool follows each selected vector (open or closed) while Z ramps from
/// `depth.startDepth` to the pass depth over `rampFraction` of the vector's length at the
/// start, end or both ends (linear, or smooth cosine for a rounded flute end). Multiple passes
/// alternate direction along the vector so there is no retract between them. A `rampFraction`
/// of 0 gives a full-length flute (plunge at the start).
///
/// Lives in Ops3D (cam-3d) as a reusable builder; `FlutingOperation.generate` (cam-2d) can
/// simply forward to `FluteToolpathGenerator.generate`.
public enum FluteToolpathGenerator {
    public static func generate(setup: OperationSetup, params: FlutingParameters,
                                in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let polylines = context.shapes(for: setup).flatMap(\.paths).compactMap { path -> [Vec2]? in
            var pts = path.flattened(tolerance: context.tolerance)
            if path.isClosed, let f = pts.first { pts.append(f) }
            return pts.count >= 2 ? pts : nil
        }
        guard !polylines.isEmpty else { throw CAMError.noGeometry }
        guard params.depth.cutDepth > params.depth.startDepth else {
            throw CAMError.invalidParameter("Flute depth must be deeper than the start depth")
        }
        let passes = params.depth.passDepths(toolStepdown: tool.stepdown)
        let clearance = context.coords.job.effectivePlungeGap(default: context.units == .inch ? 0.04 : 1.0)
        var writer = PathWriter3D(coords: context.coords, feedRate: tool.feedRate, plungeRate: tool.plungeRate,
                                  clearance: clearance)
        for line in polylines {
            let stations = Self.stations(line, params: params)
            for (k, pass) in passes.enumerated() {
                let ordered = k % 2 == 0 ? stations : stations.reversed()
                let pts = ordered.map { Vec3($0.point, z: Self.depth(weight: $0.weight, pass: pass, params: params)) }
                if k == 0 {
                    writer.enter(at: pts[0].xy, depth: pts[0].z, approachDepth: params.depth.startDepth - clearance)
                } else {
                    writer.cut(to: pts[0].xy, depth: pts[0].z)
                }
                writer.cut(through: Array(pts.dropFirst()))
            }
            writer.retract()
        }
        let moves = writer.finish()
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .fluting, tool: tool, moves: moves)]
    }

    /// Depth of a station with ramp weight `w` (0 = start depth, 1 = full pass depth).
    static func depth(weight w: Double, pass: Double, params: FlutingParameters) -> Double {
        params.depth.startDepth + (pass - params.depth.startDepth) * w
    }

    /// Points along the polyline with their ramp weight; ramp zones are densely subdivided so
    /// the Z profile follows the ramp curve.
    static func stations(_ line: [Vec2], params: FlutingParameters) -> [(point: Vec2, weight: Double)] {
        var cumulative = [0.0]
        for i in 1..<line.count { cumulative.append(cumulative[i - 1] + line[i - 1].distance(to: line[i])) }
        let total = cumulative.last!
        let fraction = min(max(params.rampFraction, 0), params.ramp == .both ? 0.5 : 1)
        let rampLength = fraction * total
        let rampsStart = params.ramp != .end, rampsEnd = params.ramp != .start
        func weight(_ s: Double) -> Double {
            guard rampLength > 1e-12 else { return 1 }
            var t = 1.0
            if rampsStart { t = min(t, s / rampLength) }
            if rampsEnd { t = min(t, (total - s) / rampLength) }
            t = min(max(t, 0), 1)
            return params.smoothRamp ? (1 - cos(.pi * t)) / 2 : t
        }
        let step = rampLength > 1e-12 ? rampLength / 24 : .infinity
        var out: [(Vec2, Double)] = [(line[0], weight(0))]
        for i in 1..<line.count {
            let a = line[i - 1], b = line[i]
            let s0 = cumulative[i - 1], len = cumulative[i] - s0
            guard len > 1e-12 else { continue }
            // Subdivide only where the segment overlaps a ramp zone.
            let inRamp = (rampsStart && s0 < rampLength) || (rampsEnd && cumulative[i] > total - rampLength)
            let n = inRamp && step.isFinite ? max(1, Int(ceil(len / step))) : 1
            for k in 1...n {
                let f = Double(k) / Double(n)
                out.append((a.lerp(to: b, f), weight(s0 + len * f)))
            }
        }
        return out
    }
}
