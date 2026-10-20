import CADCore
import Foundation

// Parameters for the 2D toolpaths added in the VCarve-parity work (toolpaths-2d).
// Lengths are in document units, depths down from the material top; defaults assume inches.

/// Where a profile cuts open vectors, relative to the vector's drawn direction.
public enum OpenVectorSide: String, Codable, CaseIterable, Sendable {
    case on, left, right
}

/// Where each closed profile loop starts cutting.
public enum ProfileStartPoint: String, Codable, CaseIterable, Sendable {
    /// The point nearest the previous position (shortest rapids; the default).
    case nearest
    /// The start node of the vector (open vectors are not reversed).
    case vectorStart
    /// The middle of a side of the loop's bounding box.
    case left, right, bottom, top
}

/// Order in which a profile cuts its parts (inner loops always before the loop around them).
public enum ProfileOrder: String, Codable, CaseIterable, Sendable {
    /// Greedy nearest neighbour (shortest rapids; the default).
    case nearest
    /// The order the vectors were selected in.
    case selection
    case leftToRight
    case bottomToTop
    /// Rows from the bottom, left to right within each row.
    case grid
}

/// Quick engrave: follow the vectors on their centreline at a fixed depth (no offset).
public struct EngraveParameters: Codable, Hashable, Sendable {
    public var depth: DepthSettings
    public var direction: CutDirection

    public init(depth: DepthSettings = DepthSettings(cutDepth: 0.0625), direction: CutDirection = .climb) {
        self.depth = depth; self.direction = direction
    }
}

/// Chamfer: a V-bit run along the vector edges so its cone cuts a bevel of `width` into the part.
public struct ChamferParameters: Codable, Hashable, Sendable {
    /// Which side of closed vectors is the part edge to bevel (outside = the part is inside the vector).
    public var side: ProfileSide
    /// Chamfer width on the top surface, measured from the vector into the part.
    public var width: Double
    /// When set, the cut depth is given directly and the width follows from the bit angle.
    public var depth: Double?
    /// Extra distance the bit tip runs into the waste past the edge (keeps the tip off the wall;
    /// the cut gets deeper to keep the same width).
    public var tipClearance: Double
    public var startDepth: Double
    /// Max depth per pass; nil = the tool's stepdown.
    public var passDepth: Double?
    public var direction: CutDirection

    public init(side: ProfileSide = .outside, width: Double = 0.125, depth: Double? = nil, tipClearance: Double = 0,
                startDepth: Double = 0, passDepth: Double? = nil, direction: CutDirection = .climb) {
        self.side = side; self.width = width; self.depth = depth; self.tipClearance = tipClearance
        self.startDepth = startDepth; self.passDepth = passDepth; self.direction = direction
    }
}
