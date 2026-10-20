import CADCore
import Foundation

/// Rotationally symmetric cutter shape: `height(r)` is how far the cutting surface sits above
/// the tool tip at radial distance `r` (0 at the tip).
public struct CutterProfile: Hashable, Sendable {
    public enum Shape: Hashable, Sendable {
        case flat
        case ball
        /// Included angle in degrees, flat tip diameter.
        case vee(angle: Double, tipDiameter: Double)
    }

    public var shape: Shape
    public var radius: Double

    public init(shape: Shape, radius: Double) { self.shape = shape; self.radius = radius }

    /// Profile matching a library tool (end mills/drills are flat, engraving bits are V).
    public init(tool: Tool) {
        switch tool.kind {
        case .endMill, .drill: self.init(shape: .flat, radius: tool.radius)
        case .ballNose: self.init(shape: .ball, radius: tool.radius)
        case .vBit, .engraving:
            self.init(shape: .vee(angle: tool.angle ?? 90, tipDiameter: tool.tipDiameter), radius: tool.radius)
        }
    }

    /// Height of the cutting surface above the tip at radial distance `r` (`r` ≤ radius).
    public func height(at r: Double) -> Double {
        switch shape {
        case .flat: return 0
        case .ball:
            let q = radius * radius - r * r
            return radius - (q > 0 ? q.squareRoot() : 0)
        case .vee(let angle, let tip):
            let half = min(max(angle, 1), 179) / 2 * .pi / 180
            return max(0, r - tip / 2) / tan(half)
        }
    }
}

/// Drop-cutter over a `ReliefHeightmap`: the deepest tip depth at an XY position such that the
/// cutter does not dip below any heightmap sample under it.
public struct DropCutter: Sendable {
    public let map: ReliefHeightmap
    public let cutter: CutterProfile

    public init(map: ReliefHeightmap, cutter: CutterProfile) { self.map = map; self.cutter = cutter }

    /// Tip depth (below the material top) at material-frame `p`. Every cell square the cutter
    /// overlaps is honoured at its point nearest the tool axis (where the cutter is lowest), so
    /// together with the heightmap's per-square minimum the result never gouges the mesh.
    /// Cells outside the map do not constrain the cutter; with none under it the result is
    /// `map.baseDepth`.
    public func depth(at p: Vec2) -> Double {
        let r = cutter.radius
        let cs = map.cellSize
        let half = cs / 2
        let i0 = max(0, Int(ceil((p.x - r - half - map.origin.x) / cs)))
        let i1 = min(map.columns - 1, Int(floor((p.x + r + half - map.origin.x) / cs)))
        let j0 = max(0, Int(ceil((p.y - r - half - map.origin.y) / cs)))
        let j1 = min(map.rows - 1, Int(floor((p.y + r + half - map.origin.y) / cs)))
        guard i0 <= i1, j0 <= j1 else { return map.baseDepth }
        var best = Double.infinity
        let r2 = r * r
        let cols = map.columns
        map.depths.withUnsafeBufferPointer { d in
            for j in j0...j1 {
                let dy = max(0, abs(map.origin.y + Double(j) * cs - p.y) - half)
                let dy2 = dy * dy
                if dy2 > r2 { continue }
                let row = j * cols
                for i in i0...i1 {
                    let dx = max(0, abs(map.origin.x + Double(i) * cs - p.x) - half)
                    let q = dx * dx + dy2
                    if q > r2 { continue }
                    let cand = d[row + i] + cutter.height(at: q.squareRoot())
                    if cand < best { best = cand }
                }
            }
        }
        return best.isFinite ? best : map.baseDepth
    }
}
