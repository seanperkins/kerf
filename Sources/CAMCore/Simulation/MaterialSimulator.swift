import CADCore
import Foundation

/// Simulates material removal of toolpaths into a `Heightfield`. Owned by the preview workstream.
///
/// Each straight motion segment is swept with the tool profile: for every cell near the
/// segment, the tool axis is placed at the closest point of the segment (in XY) and the cell is
/// lowered to the cutting surface there. Segments that change Z are subdivided so each piece
/// descends at most about one cell size, which keeps ramps and helices accurate.
/// Cut depth is clamped to the material thickness (through-cuts).
public struct MaterialSimulator: Sendable {
    public var heightfield: Heightfield
    public var coords: MachineCoordinates

    public init(job: JobSetup, cellSize: Double) {
        coords = MachineCoordinates(job: job)
        heightfield = Heightfield(width: job.width, height: job.height, cellSize: cellSize)
    }

    /// Carves every move of `toolpath` with its tool.
    public mutating func apply(_ toolpath: Toolpath) {
        let shape = ToolShape(tool: toolpath.tool)
        for seg in MotionPath.segments(of: toolpath.moves, arcTolerance: arcTolerance) {
            apply(seg, shape: shape)
        }
    }

    /// Chord tolerance used when flattening arcs (half a cell).
    public var arcTolerance: Double { max(heightfield.cellSize / 2, 1e-4) }

    /// Carves one machine-coordinate segment; `fraction` < 1 carves only its first part
    /// (used to show a move in progress).
    public mutating func apply(_ segment: MotionSegment, shape: ToolShape, fraction: Double = 1) {
        let f = min(max(fraction, 0), 1)
        let a = coords.material(fromMachine: segment.start)
        let endMachine = f < 1 ? segment.point(at: f) : segment.end
        let b = coords.material(fromMachine: endMachine)
        carve(from: a.xy, depth: a.depth, to: b.xy, depth: b.depth, shape: shape)
    }

    /// Carves a straight sweep in the material frame (depths below the material top).
    public mutating func carve(from p0: Vec2, depth d0: Double, to p1: Vec2, depth d1: Double,
                               shape: ToolShape) {
        guard max(d0, d1) > 0 else { return } // entirely above the stock
        let cs = heightfield.cellSize
        let r = shape.radius
        let xyLength = p0.distance(to: p1)
        // Pieces: ≤ one cell of descent each, and short enough to keep bounding boxes tight.
        let byZ = Int(ceil(abs(d1 - d0) / cs))
        let byXY = Int(ceil(xyLength / max(8 * r, 16 * cs)))
        let n = max(1, min(100_000, max(byZ, byXY)))
        var prevP = p0, prevD = d0
        for k in 1...n {
            let t = Double(k) / Double(n)
            let p = k == n ? p1 : p0.lerp(to: p1, t)
            let d = k == n ? d1 : d0 + (d1 - d0) * t
            carvePiece(prevP, prevD, p, d, shape: shape)
            prevP = p; prevD = d
        }
    }

    private mutating func carvePiece(_ p0: Vec2, _ d0: Double, _ p1: Vec2, _ d1: Double, shape: ToolShape) {
        guard max(d0, d1) > 0 else { return }
        let hf = heightfield
        let cs = hf.cellSize
        let r = shape.radius
        let minX = min(p0.x, p1.x) - r, maxX = max(p0.x, p1.x) + r
        let minY = min(p0.y, p1.y) - r, maxY = max(p0.y, p1.y) + r
        let i0 = max(0, Int(floor(minX / cs - 0.5))), i1 = min(hf.columns - 1, Int(ceil(maxX / cs - 0.5)))
        let j0 = max(0, Int(floor(minY / cs - 0.5))), j1 = min(hf.rows - 1, Int(ceil(maxY / cs - 0.5)))
        guard i0 <= i1, j0 <= j1 else { return }
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len2 = dx * dx + dy * dy
        let thickness = Float(coords.job.thickness)
        let columns = hf.columns
        let r2 = r * r
        heightfield.depths.withUnsafeMutableBufferPointer { buf in
            for j in j0...j1 {
                let cy = (Double(j) + 0.5) * cs
                for i in i0...i1 {
                    let cx = (Double(i) + 0.5) * cs
                    var t = 0.0
                    if len2 > 1e-24 {
                        t = ((cx - p0.x) * dx + (cy - p0.y) * dy) / len2
                        t = min(max(t, 0), 1)
                    }
                    let qx = p0.x + dx * t - cx, qy = p0.y + dy * t - cy
                    let dist2 = qx * qx + qy * qy
                    guard dist2 <= r2, let h = shape.heightAboveTip(atRadius: dist2.squareRoot()) else { continue }
                    let tip = len2 > 1e-24 ? d0 + (d1 - d0) * t : max(d0, d1)
                    let cut = Float(tip - h)
                    guard cut > 0 else { continue }
                    let idx = j * columns + i
                    let newDepth = min(cut, thickness)
                    if newDepth > buf[idx] { buf[idx] = newDepth }
                }
            }
        }
    }
}
