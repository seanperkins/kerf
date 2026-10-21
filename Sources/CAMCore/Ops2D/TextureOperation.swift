import CADCore
import Foundation

/// Texture: pseudo-random shallow strokes inside the selected boundary (seeded, reproducible).
public struct TextureOperation: ToolpathOperation {
    public static let kind = OperationKind.texture
    public var setup: OperationSetup
    public var params: TextureParameters

    public init(setup: OperationSetup, params: TextureParameters = TextureParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let tool = try context.tool(setup.toolID)
        let shapes = context.shapes(for: setup)
        guard !shapes.isEmpty else { throw CAMError.noGeometry }
        let p = params
        guard p.maxDepth > 0, p.spacing > 0, p.maxStrokeLength > 0 else {
            throw CAMError.invalidParameter("Depth, spacing and stroke length must be positive")
        }
        let tol = context.tolerance
        let closed = ShapeGeometry.loops(of: shapes, tolerance: tol).closed
        let region = Polygon2D.region(fromLoops: closed)
        guard !region.isEmpty else { throw CAMError.invalidGeometry("Texturing needs closed vectors") }

        let strokes = Self.strokes(in: region, params: p, tolerance: tol)
        guard !strokes.isEmpty else { throw CAMError.invalidGeometry("The region is too small for a texture stroke") }
        var b = ToolpathBuilder(coords: context.coords, tool: tool, units: context.units, tolerance: tol)
        for s in strokes {
            b.cutChain(s)
            b.retract()
        }
        return [Toolpath(name: setup.name, operationID: setup.id, kind: .texture, tool: tool, moves: b.finish(),
                         metadata: ["strokes": "\(strokes.count)"])]
    }

    /// Strokes laid along parallel lines, serpentine order. Each stroke dips smoothly from
    /// the surface to its depth and back.
    static func strokes(in region: [[Vec2]], params p: TextureParameters, tolerance: Double) -> [[CutPoint]] {
        var rng = SplitMix64(seed: p.seed)
        let v = min(max(p.variation, 0), 1)
        let minLen = max(min(p.minStrokeLength, p.maxStrokeLength), tolerance * 10)
        let planner = PocketPlanner(region: region, toolRadius: 0, stepover: p.spacing, allowance: 0,
                                    tolerance: tolerance, direction: .climb)
        let lines = planner.rasterLines(in: region, angle: p.angle)
        let dir = Vec2(cos(p.angle * .pi / 180), sin(p.angle * .pi / 180))
        let normal = dir.perpendicular
        // Group clipped segments by their raster line (signed offset along the normal).
        let keyed = lines.map { seg -> (Double, [Vec2]) in
            let mid = seg[0].lerp(to: seg.last!, 0.5)
            let ordered = (seg.last! - seg[0]).dot(dir) >= 0 ? seg : Array(seg.reversed())
            return ((mid.dot(normal) / p.spacing).rounded(), ordered)
        }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1[0].dot(dir) < $1.1[0].dot(dir) }

        var out: [[CutPoint]] = []
        var lineStrokes: [[CutPoint]] = []
        var currentKey: Double?
        var reverse = false
        func flush() {
            out += reverse ? lineStrokes.reversed().map { $0.reversed() } : lineStrokes
            lineStrokes = []
            reverse.toggle()
        }
        for (key, seg) in keyed {
            if let c = currentKey, c != key { flush() }
            currentKey = key
            let a = seg[0], bEnd = seg.last!
            let segLen = a.distance(to: bEnd)
            var t = rng.next() * p.spacing * (0.5 + v)
            while t < segLen {
                let len = minLen + (p.maxStrokeLength - minLen) * rng.next()
                let end = min(t + len, segLen)
                if end - t >= minLen * 0.5 {
                    let jitter = (rng.next() - 0.5) * v * p.spacing * 0.5
                    let depth = p.maxDepth * (1 - v * 0.6 * rng.next())
                    let s0 = a + dir * t + normal * jitter, s1 = a + dir * end + normal * jitter
                    if Polygon2D.regionContains(region, s0), Polygon2D.regionContains(region, s1) {
                        let n = 8
                        lineStrokes.append((0...n).map { i in
                            let u = Double(i) / Double(n)
                            return CutPoint(s0.lerp(to: s1, u), depth: depth * sin(.pi * u))
                        })
                    }
                }
                t = end + p.spacing * (0.25 + v * rng.next())
            }
        }
        if !lineStrokes.isEmpty { flush() }
        return out
    }
}

/// Small deterministic PRNG (SplitMix64) so textures are reproducible from their seed.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func next() -> Double { Double(nextUInt64() >> 11) / Double(1 << 53) }
}
