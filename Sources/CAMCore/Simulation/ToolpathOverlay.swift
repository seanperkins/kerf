import CADCore
import Foundation

/// Material-frame polylines for drawing toolpaths over the 2D design: rapids (to be drawn
/// dashed) and cuts bucketed by depth (to be coloured with `DepthColorRamp.toolpath`).
public struct ToolpathOverlay: Sendable {
    public struct Stroke: Hashable, Sendable {
        public var points: [Vec2]
        public var isRapid: Bool
        /// Deepest point of the stroke below the material top (0 for rapids).
        public var depth: Double
        public var toolpathIndex: Int
    }

    /// Vertical feed moves into the stock (drilling, plunges): material XY and depth.
    public struct Plunge: Hashable, Sendable {
        public var point: Vec2
        public var depth: Double
        public var toolpathIndex: Int
    }

    public var strokes: [Stroke] = []
    public var plunges: [Plunge] = []
    /// Deepest cut seen (for normalising colours).
    public var maxDepth: Double = 0

    public init() {}

    /// - Parameters:
    ///   - depthBuckets: a cut polyline is split whenever its depth changes bucket, so a
    ///     renderer can colour each stroke with a single colour.
    public init(toolpaths: [Toolpath], coords: MachineCoordinates, arcTolerance: Double = 0.005,
                depthBuckets: Int = 16) {
        let bucketSize = max(coords.job.thickness, 1e-9) / Double(max(1, depthBuckets))
        for (ti, tp) in toolpaths.enumerated() {
            var current: Stroke?
            var currentBucket = -1
            func flush() {
                if let s = current, s.points.count >= 2 { strokes.append(s) }
                current = nil
            }
            for seg in MotionPath.segments(of: tp.moves, arcTolerance: arcTolerance) {
                let a = coords.material(fromMachine: seg.start)
                let b = coords.material(fromMachine: seg.end)
                if a.xy.distance(to: b.xy) < 1e-9 {
                    if !seg.isRapid, b.depth > a.depth, b.depth > 0 {
                        plunges.append(Plunge(point: b.xy, depth: b.depth, toolpathIndex: ti))
                        maxDepth = max(maxDepth, b.depth)
                    }
                    continue
                }
                let depth = seg.isRapid ? 0 : max(0, max(a.depth, b.depth))
                maxDepth = max(maxDepth, depth)
                let bucket = seg.isRapid ? -2 : Int(depth / bucketSize)
                if var s = current, s.isRapid == seg.isRapid, bucket == currentBucket,
                   s.points.last.map({ $0.isApproximatelyEqual(to: a.xy, tolerance: 1e-9) }) == true {
                    s.points.append(b.xy)
                    s.depth = max(s.depth, depth)
                    current = s
                } else {
                    flush()
                    current = Stroke(points: [a.xy, b.xy], isRapid: seg.isRapid, depth: depth, toolpathIndex: ti)
                    currentBucket = bucket
                }
            }
            flush()
        }
    }
}
