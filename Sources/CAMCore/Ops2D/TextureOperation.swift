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
        // A raster line is a run of clipped pieces at one signed offset along the normal; they differ by clipping
        // rounding only. The lines themselves can be arbitrarily close in a region narrower than the spacing (a row on
        // each edge), so what separates two lines is the geometry tolerance, not a fraction of the spacing.
        let rowGap = min(p.spacing * 0.25, max(tolerance * 0.5, 1e-6))
        let pieces = lines.map { seg -> (offset: Double, seg: [Vec2]) in
            let mid = seg[0].lerp(to: seg.last!, 0.5)
            let ordered = (seg.last! - seg[0]).dot(dir) >= 0 ? seg : Array(seg.reversed())
            return (mid.dot(normal), ordered)
        }.sorted { $0.offset < $1.offset }
        var rows: [[[Vec2]]] = []
        var rowOffset = -Double.infinity
        for piece in pieces {
            if piece.offset - rowOffset > rowGap { rows.append([]); rowOffset = piece.offset }
            rows[rows.count - 1].append(piece.seg)
        }

        // Serpentine: every other row is cut back to front.
        var out: [[CutPoint]] = []
        for (index, row) in rows.enumerated() {
            var rowStrokes: [[CutPoint]] = []
            for seg in row.sorted(by: { $0[0].dot(dir) < $1[0].dot(dir) }) {
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
                            rowStrokes.append((0...n).map { i in
                                let u = Double(i) / Double(n)
                                return CutPoint(s0.lerp(to: s1, u), depth: depth * sin(.pi * u))
                            })
                        }
                    }
                    t = end + p.spacing * (0.25 + v * rng.next())
                }
            }
            out += index % 2 == 1 ? rowStrokes.reversed().map { $0.reversed() } : rowStrokes
        }
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
