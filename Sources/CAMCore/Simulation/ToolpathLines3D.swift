// Toolpath centre lines in 3D (material frame) for the 3D preview. Owned by preview.
import CADCore
import Foundation

/// Tool-tip polylines of a set of toolpaths in the material frame (x, y, z = -depth below the
/// material top), split wherever motion switches between rapid and feed or the toolpath changes.
public struct ToolpathLines3D: Sendable, Equatable {
    public struct Polyline: Hashable, Sendable {
        public var points: [Vec3]
        public var isRapid: Bool
        public var toolpathIndex: Int
    }

    public var polylines: [Polyline] = []
    /// Deepest feed point below the material top (for normalising colours).
    public var maxDepth: Double = 0

    public init() {}

    public init(toolpaths: [Toolpath], coords: MachineCoordinates, arcTolerance: Double = 0.005) {
        for (ti, tp) in toolpaths.enumerated() {
            var current: Polyline?
            func flush() {
                if let c = current, c.points.count >= 2 { polylines.append(c) }
                current = nil
            }
            for seg in MotionPath.segments(of: tp.moves, arcTolerance: arcTolerance) {
                let a = coords.material(fromMachine: seg.start)
                let b = coords.material(fromMachine: seg.end)
                let pa = Vec3(a.xy, z: -a.depth), pb = Vec3(b.xy, z: -b.depth)
                if !seg.isRapid { maxDepth = max(maxDepth, a.depth, b.depth) }
                if var c = current, c.isRapid == seg.isRapid,
                   let last = c.points.last, last.distance(to: pa) < 1e-9 {
                    if pb.distance(to: last) >= 1e-12 { c.points.append(pb) }
                    current = c
                } else {
                    flush()
                    current = Polyline(points: [pa, pb], isRapid: seg.isRapid, toolpathIndex: ti)
                }
            }
            flush()
        }
    }

    /// Total number of straight pieces (for sizing geometry buffers).
    public var segmentCount: Int { polylines.reduce(0) { $0 + max(0, $1.points.count - 1) } }
}
