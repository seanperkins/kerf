import CADCore
import Foundation

/// Texture toolpaths: rows of short scoop-shaped strokes along `angle`, spaced by `spacing`,
/// with stroke length, gap, row offset and depth randomised by `variation` from a seeded PRNG
/// (same parameters + seed → identical toolpath). Each stroke dips smoothly from the material
/// top to its depth and back (half-sine), which suits ball-nose and V-bits. The textured area
/// is the union of the selected closed vectors, or the whole material when none are selected.
///
/// Lives in Ops3D (cam-3d) as a reusable builder; `TextureOperation.generate` (cam-2d) can
/// simply forward to `TextureToolpathGenerator.generate`.
public enum TextureToolpathGenerator {
    public static func generate(setup: OperationSetup, params: TextureParameters,
                                in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        guard params.spacing > 0, params.maxDepth > 0, params.maxStrokeLength > 0 else {
            throw CAMError.invalidParameter("Texture spacing, depth and stroke length must be > 0")
        }
        let shapes = context.shapes(for: setup)
        var region = ReliefRegion.polygons(of: shapes, tolerance: context.tolerance)
        if region.isEmpty {
            guard shapes.isEmpty else { throw CAMError.invalidGeometry("Texture needs closed vectors") }
            region = [ReliefRegion.rectangle(context.document.job.materialBounds)]
        }
        let variation = min(max(params.variation, 0), 1)
        let minLen = max(min(params.minStrokeLength, params.maxStrokeLength), tool.diameter * 0.5, 1e-4)
        let maxLen = max(params.maxStrokeLength, minLen)
        guard let range = RasterPattern.offsetRange(region: region, angleDegrees: params.angle) else {
            throw CAMError.noGeometry
        }
        var rng = ReliefSplitMix64(seed: params.seed)

        // Row offsets with jitter (never crossing the neighbouring row).
        var offsets: [Double] = []
        var s = range.lowerBound + params.spacing / 2
        while s < range.upperBound {
            offsets.append(s + (rng.unit() - 0.5) * variation * params.spacing * 0.5)
            s += params.spacing
        }
        let pattern = RasterPattern(region: region, angleDegrees: params.angle, offsets: offsets)

        let clearance = context.units == .inch ? 0.04 : 1.0
        var writer = PathWriter3D(coords: context.coords, feedRate: tool.feedRate, plungeRate: tool.plungeRate,
                                  clearance: clearance)
        let hop = 2 * maxLen
        for (row, segments) in pattern.lines.enumerated() {
            let ordered = row % 2 == 0 ? segments
                : segments.reversed().map { RasterPattern.Segment(start: $0.end, end: $0.start) }
            for seg in ordered {
                let length = seg.start.distance(to: seg.end)
                let dir = (seg.end - seg.start) / max(length, 1e-12)
                var t = rng.unit() * minLen * (0.25 + variation)
                while t < length {
                    let strokeLength = min(minLen + (maxLen - minLen) * rng.unit(), length - t)
                    let depth = params.maxDepth * (1 - 0.7 * variation * rng.unit())
                    let gap = minLen * (0.15 + variation * rng.unit())
                    defer { t += strokeLength + gap }
                    guard strokeLength >= minLen * 0.5 else { continue }
                    let a = seg.start + dir * t, b = seg.start + dir * (t + strokeLength)
                    Self.stroke(from: a, to: b, depth: depth, writer: &writer, hop: hop, clearance: clearance)
                }
            }
            writer.retract()
        }
        let moves = writer.finish()
        guard moves.count > 1 else { throw CAMError.noGeometry }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .texture, tool: tool, moves: moves)]
    }

    /// One half-sine scoop from `a` to `b`. Nearby strokes are linked by feeding just above the
    /// material top instead of retracting to safe Z.
    private static func stroke(from a: Vec2, to b: Vec2, depth: Double, writer: inout PathWriter3D,
                               hop: Double, clearance: Double) {
        if let p = writer.position, !writer.isAtSafeZ, p.xy.distance(to: a) <= hop {
            writer.cut(to: p.xy, depth: -clearance)
            writer.cut(to: a, depth: -clearance)
            writer.cut(to: a, depth: 0)
        } else {
            writer.enter(at: a, depth: 0)
        }
        let n = 16
        for k in 1...n {
            let f = Double(k) / Double(n)
            writer.cut(to: a.lerp(to: b, f), depth: depth * sin(.pi * f))
        }
    }
}

/// Small deterministic PRNG (SplitMix64) so textures are reproducible across runs/platforms.
struct ReliefSplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
