import CADCore
import Foundation

/// Material stock as a grid of top-surface depths for the removal simulation.
/// Material frame: cell (i, j) covers x = i*cellSize..., y = j*cellSize... from the material's
/// lower-left. Values are DEPTH below the original material top (0 = untouched).
public struct Heightfield: Hashable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellSize: Double
    public var depths: [Float]

    public init(width: Double, height: Double, cellSize: Double) {
        self.cellSize = cellSize
        columns = max(1, Int(ceil(width / cellSize)))
        rows = max(1, Int(ceil(height / cellSize)))
        depths = Array(repeating: 0, count: columns * rows)
    }

    public subscript(i: Int, j: Int) -> Float {
        get { depths[j * columns + i] }
        set { depths[j * columns + i] = newValue }
    }
}

/// Simulates material removal of toolpaths into a `Heightfield`. Owned by the preview workstream.
public struct MaterialSimulator: Sendable {
    public var heightfield: Heightfield
    public var coords: MachineCoordinates

    public init(job: JobSetup, cellSize: Double) {
        coords = MachineCoordinates(job: job)
        heightfield = Heightfield(width: job.width, height: job.height, cellSize: cellSize)
    }

    public mutating func apply(_ toolpath: Toolpath) {
        // TODO(preview): sweep tool profile (flat/ball/V) along each move.
    }
}

/// Machining-time estimate (feeds + rapids, no acceleration model). Owned by preview.
public enum MachiningTimeEstimator {
    /// - Parameter rapidRate: machine rapid speed in document units per minute.
    public static func estimate(_ toolpaths: [Toolpath], rapidRate: Double) -> TimeInterval {
        // TODO(preview): sum move lengths / feed (arcs by arc length), add tool-change allowance.
        0
    }
}
