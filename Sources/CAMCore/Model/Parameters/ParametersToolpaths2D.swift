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

/// What a chamfer's depth and width are measured from when its start depth is not 0 (issue #51).
public enum ChamferBasis: String, Codable, Hashable, Sendable {
    /// The surface at the start depth, where the material above is already gone (every other operation's meaning).
    case startSurface
    /// The material top: the depth is the tip's depth below it, the width is on it, and the start depth only skips
    /// the passes above it. What files saved before the basis was chosen mean, so they cut as they always did.
    case materialTop
}

/// Chamfer: a V-bit run along the vector edges so its cone cuts a bevel of `width` into the part.
public struct ChamferParameters: Codable, Hashable, Sendable {
    /// Which side of closed vectors is the part edge to bevel (outside = the part is inside the vector).
    public var side: ProfileSide
    /// Chamfer width on the `basis` surface (the material top when the start depth is 0), measured from the
    /// vector into the part.
    public var width: Double
    /// When set, how far the tip goes below the `basis` surface, and the width follows from the bit angle.
    public var depth: Double?
    /// Extra distance the bit tip runs into the waste past the edge (keeps the tip off the wall;
    /// the cut gets deeper to keep the same width).
    public var tipClearance: Double
    public var startDepth: Double
    /// What the depth and width are measured from. A file without the key predates the choice and keeps the
    /// material top; new chamfers measure from the start depth's surface.
    public var basis: ChamferBasis
    /// Max depth per pass; nil = the tool's stepdown.
    public var passDepth: Double?
    public var direction: CutDirection

    public init(side: ProfileSide = .outside, width: Double = 0.125, depth: Double? = nil, tipClearance: Double = 0,
                startDepth: Double = 0, basis: ChamferBasis = .startSurface, passDepth: Double? = nil,
                direction: CutDirection = .climb) {
        self.side = side; self.width = width; self.depth = depth; self.tipClearance = tipClearance
        self.startDepth = startDepth; self.basis = basis; self.passDepth = passDepth; self.direction = direction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        side = try c.decode(ProfileSide.self, forKey: .side)
        width = try c.decode(Double.self, forKey: .width)
        depth = try c.decodeIfPresent(Double.self, forKey: .depth)
        tipClearance = try c.decode(Double.self, forKey: .tipClearance)
        startDepth = try c.decode(Double.self, forKey: .startDepth)
        basis = try c.decodeIfPresent(ChamferBasis.self, forKey: .basis) ?? .materialTop
        passDepth = try c.decodeIfPresent(Double.self, forKey: .passDepth)
        direction = try c.decode(CutDirection.self, forKey: .direction)
    }
}

public enum HoleMillMode: String, Codable, CaseIterable, Sendable {
    /// Helical boring: spiral down to the cut depth at the hole radius, then a flat lap.
    case helical
    /// Internal thread milling with a thread mill (needs a pilot hole).
    case thread
}

/// Hole milling: helical bores and internal threads at each selected circle.
public struct HoleMillParameters: Codable, Hashable, Sendable {
    public var mode: HoleMillMode
    public var startDepth: Double
    public var cutDepth: Double
    /// Hole (or thread major) diameter; nil = each vector's own diameter.
    public var holeDiameter: Double?
    /// Helical boring: depth per revolution; nil = the tool's stepdown.
    public var helixPitch: Double?
    /// Thread pitch (distance per turn), e.g. 1/16 in for 16 TPI.
    public var threadPitch: Double
    public var rightHandThread: Bool
    public var direction: CutDirection

    public init(mode: HoleMillMode = .helical, startDepth: Double = 0, cutDepth: Double = 0.5,
                holeDiameter: Double? = nil, helixPitch: Double? = nil, threadPitch: Double = 0.0625,
                rightHandThread: Bool = true, direction: CutDirection = .climb) {
        self.mode = mode; self.startDepth = startDepth; self.cutDepth = cutDepth; self.holeDiameter = holeDiameter
        self.helixPitch = helixPitch; self.threadPitch = threadPitch; self.rightHandThread = rightHandThread
        self.direction = direction
    }
}

/// Prism carving: a V-bit runs round each shape's outline deep enough that its flanks meet in a
/// sharp ridge along the shape's centreline, so the shape is carved as a bevelled prism.
public struct PrismParameters: Codable, Hashable, Sendable {
    /// Depth limit; wide parts deeper than this keep a flat top. nil = no limit.
    public var maxDepth: Double?
    /// Max depth per pass; nil = the tool's stepdown.
    public var passDepth: Double?
    public var direction: CutDirection

    public init(maxDepth: Double? = nil, passDepth: Double? = nil, direction: CutDirection = .climb) {
        self.maxDepth = maxDepth; self.passDepth = passDepth; self.direction = direction
    }
}

/// Per-toolpath changes to the primary tool's cutting data, in document units. nil fields keep
/// the tool database value (toolpaths-2d addition).
public struct ToolOverride: Codable, Hashable, Sendable {
    public var spindleRPM: Double?
    public var feedRate: Double?
    public var plungeRate: Double?
    public var stepdown: Double?
    public var stepover: Double?

    public init(spindleRPM: Double? = nil, feedRate: Double? = nil, plungeRate: Double? = nil,
                stepdown: Double? = nil, stepover: Double? = nil) {
        self.spindleRPM = spindleRPM; self.feedRate = feedRate; self.plungeRate = plungeRate
        self.stepdown = stepdown; self.stepover = stepover
    }

    public var isEmpty: Bool {
        spindleRPM == nil && feedRate == nil && plungeRate == nil && stepdown == nil && stepover == nil
    }

    /// `tool` (already in document units) with the set fields replaced.
    public func applied(to tool: Tool) -> Tool {
        var t = tool
        if let v = spindleRPM, v > 0 { t.spindleRPM = v }
        if let v = feedRate, v > 0 { t.feedRate = v }
        if let v = plungeRate, v > 0 { t.plungeRate = v }
        if let v = stepdown, v > 0 { t.stepdown = v }
        if let v = stepover, v > 0 { t.stepover = v }
        return t
    }
}

/// Repeats a toolpath on a grid without copying its vectors (toolpaths-2d addition).
public struct ArrayCopySettings: Codable, Hashable, Sendable {
    public var columns: Int
    public var rows: Int
    /// Distance between copies along X / Y (document units; negative = left / down).
    public var spacingX: Double
    public var spacingY: Double

    public init(columns: Int = 2, rows: Int = 1, spacingX: Double = 6, spacingY: Double = 6) {
        self.columns = columns; self.rows = rows; self.spacingX = spacingX; self.spacingY = spacingY
    }

    public var count: Int { max(columns, 1) * max(rows, 1) }

    /// Copy offsets in cutting order: rows from the first, alternating direction (serpentine).
    public var offsets: [Vec2] {
        var out: [Vec2] = []
        for j in 0..<max(rows, 1) {
            let cols = Array(0..<max(columns, 1))
            for i in j % 2 == 0 ? cols : cols.reversed() {
                out.append(Vec2(Double(i) * spacingX, Double(j) * spacingY))
            }
        }
        return out
    }
}

/// The toolpaths a merged toolpath cuts, in order (toolpaths-2d addition).
public struct MergeParameters: Codable, Hashable, Sendable {
    public var children: [AnyOperation]

    public init(children: [AnyOperation] = []) { self.children = children }
}

/// Straight-wall (end mill) inlay: a pocket and a matching plug cut round the same outline, with
/// every corner rounded to what the end mill can cut on both parts (toolpaths-2d addition).
public struct StraightInlayParameters: Codable, Hashable, Sendable {
    /// Pocket, plug or both (both = one program; normally cut each part on its own board).
    public var part: InlayPart
    public var pocketDepth: Double
    /// Depth of the plug's outside profile (usually a little more than the pocket depth).
    public var plugDepth: Double
    /// Gap all round between plug and pocket wall (the plug is made this much smaller).
    public var clearance: Double
    /// Mirror the plug left-right (for plugs glued in face down).
    public var mirrorPlug: Bool
    /// Max depth per pass; nil = the tool's stepdown.
    public var passDepth: Double?

    public init(part: InlayPart = .female, pocketDepth: Double = 0.125, plugDepth: Double = 0.1875,
                clearance: Double = 0.003, mirrorPlug: Bool = false, passDepth: Double? = nil) {
        self.part = part; self.pocketDepth = pocketDepth; self.plugDepth = plugDepth; self.clearance = clearance
        self.mirrorPlug = mirrorPlug; self.passDepth = passDepth
    }
}

/// Moulding: sweeps a cross-section vector along rail vectors (toolpaths-2d addition).
public struct MouldingParameters: Codable, Hashable, Sendable {
    /// The cross-section vector. Its bounding box maps X → distance from the rail (min X on the
    /// rail) and Y → height (max Y = the material top, lower = deeper).
    public var sectionShapeID: UUID?
    /// Which side of open rails the section extends to (closed rails: inside).
    public var side: OpenVectorSide
    /// Extra depth added under the whole section (0 = the section's top is the material top).
    public var startDepth: Double
    /// Distance between passes across the section; nil = the tool's stepover.
    public var stepover: Double?
    /// Rough in levels of the tool's stepdown before the finishing passes.
    public var roughing: Bool

    public init(sectionShapeID: UUID? = nil, side: OpenVectorSide = .left, startDepth: Double = 0,
                stepover: Double? = nil, roughing: Bool = true) {
        self.sectionShapeID = sectionShapeID; self.side = side; self.startDepth = startDepth
        self.stepover = stepover; self.roughing = roughing
    }
}
