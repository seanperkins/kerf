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

    /// Material-frame centre of cell (i, j).
    public func cellCenter(_ i: Int, _ j: Int) -> Vec2 {
        Vec2((Double(i) + 0.5) * cellSize, (Double(j) + 0.5) * cellSize)
    }

    /// Cell containing material-frame point `p`, or nil when outside the stock.
    public func cell(containing p: Vec2) -> (i: Int, j: Int)? {
        let i = Int(floor(p.x / cellSize)), j = Int(floor(p.y / cellSize))
        guard i >= 0, j >= 0, i < columns, j < rows else { return nil }
        return (i, j)
    }

    /// Depth at material-frame point `p` (0 outside the stock).
    public func depth(at p: Vec2) -> Float {
        guard let c = cell(containing: p) else { return 0 }
        return self[c.i, c.j]
    }

    /// Deepest cell value.
    public var maxDepth: Float { depths.max() ?? 0 }

    /// Resets every cell to the untouched top.
    public mutating func reset() {
        for k in depths.indices { depths[k] = 0 }
    }

    /// Cell size giving roughly `targetCells` cells over the material (never below `minimum`).
    public static func automaticCellSize(width: Double, height: Double, targetCells: Double = 1_000_000,
                                         minimum: Double = 0) -> Double {
        let area = max(width * height, 1e-12)
        return max(minimum, (area / targetCells).squareRoot())
    }
}
