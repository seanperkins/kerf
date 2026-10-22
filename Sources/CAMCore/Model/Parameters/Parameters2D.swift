import CADCore
import Foundation

public enum ProfileSide: String, Codable, CaseIterable, Sendable {
    case outside, inside, on
}

public struct TabSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var length: Double
    /// Tab height above the final cut depth.
    public var thickness: Double
    /// Automatic: number of tabs evenly spaced per closed path.
    public var countPerPath: Int
    /// Triangular (ramped) tabs instead of rectangular.
    public var isTriangular: Bool
    /// Optional distance between tabs; when set it overrides `countPerPath` (cam-2d addition).
    public var spacing: Double?
    /// User-placed tabs (the tab editor). When non-nil the automatic layout is skipped and each
    /// anchor puts one tab on the toolpath loop its own vector produced; loops with no anchor get
    /// none, and an anchor whose vector is not cut by the toolpath is reported, not moved.
    public var manualTabs: [TabAnchor]?

    public init(isEnabled: Bool = false, length: Double = 0.25, thickness: Double = 0.125,
                countPerPath: Int = 4, isTriangular: Bool = false, spacing: Double? = nil,
                manualTabs: [TabAnchor]? = nil) {
        self.isEnabled = isEnabled; self.length = length; self.thickness = thickness
        self.countPerPath = countPerPath; self.isTriangular = isTriangular; self.spacing = spacing
        self.manualTabs = manualTabs
    }

    /// True when tabs come from user-placed anchors instead of the automatic layout.
    public var isManual: Bool { manualTabs != nil }
}

/// A user-placed tab: a position along one path of a vector, as a fraction of that path's
/// flattened length (so the tab follows the vector when it is moved, scaled or rotated).
public struct TabAnchor: Codable, Hashable, Sendable {
    public var shapeID: UUID
    public var pathIndex: Int
    /// 0 ..< 1 along the path, measured from its start point.
    public var fraction: Double

    public init(shapeID: UUID, pathIndex: Int = 0, fraction: Double) {
        self.shapeID = shapeID; self.pathIndex = pathIndex; self.fraction = fraction
    }
}

public enum LeadType: String, Codable, CaseIterable, Sendable { case none, linear, arc }

public struct LeadSettings: Codable, Hashable, Sendable {
    public var type: LeadType
    /// Lead length (linear) or radius (arc).
    public var distance: Double
    /// Extra distance cut past the start point on closed paths.
    public var overcut: Double

    public init(type: LeadType = .none, distance: Double = 0.25, overcut: Double = 0) {
        self.type = type; self.distance = distance; self.overcut = overcut
    }
}

/// Separate finishing (last) pass for profiles: the roughing passes leave `allowance` on the
/// wall, then one more lap removes it (toolpaths-2d addition).
public struct ProfileLastPass: Codable, Hashable, Sendable {
    /// Side allowance the roughing passes leave for the last pass (> 0).
    public var allowance: Double
    /// Cut the last pass in the opposite direction (climb ↔ conventional).
    public var reverseDirection: Bool
    /// Cut the last pass at full depth in one go (otherwise it repeats the depth passes).
    public var fullDepth: Bool

    public init(allowance: Double = 0.01, reverseDirection: Bool = false, fullDepth: Bool = true) {
        self.allowance = allowance; self.reverseDirection = reverseDirection; self.fullDepth = fullDepth
    }
}

public struct ProfileParameters: Codable, Hashable, Sendable {
    public var depth: DepthSettings
    public var side: ProfileSide
    public var direction: CutDirection
    /// Extra material left (positive) or removed (negative) beyond the vector.
    public var allowance: Double
    public var tabs: TabSettings
    public var ramp: RampSettings
    public var lead: LeadSettings
    /// Use G2/G3 where the offset contains true arcs (otherwise everything is linear).
    public var preferArcs: Bool
    /// Optional separate last pass (nil = off; optional so older files decode unchanged).
    public var lastPass: ProfileLastPass?
    /// Side for open vectors (nil = on the line, as before; toolpaths-2d addition).
    public var openVectorSide: OpenVectorSide?
    /// Where closed loops start (nil = nearest; toolpaths-2d addition).
    public var startPoint: ProfileStartPoint?
    /// Part cutting order (nil = nearest; toolpaths-2d addition).
    public var order: ProfileOrder?
    /// Keep the toolpath square at the part's external corners instead of rolling round them
    /// (nil/false = round; toolpaths-2d addition).
    public var sharpCorners: Bool?

    public init(depth: DepthSettings = DepthSettings(cutDepth: 0.75), side: ProfileSide = .outside,
                direction: CutDirection = .climb, allowance: Double = 0, tabs: TabSettings = TabSettings(),
                ramp: RampSettings = RampSettings(), lead: LeadSettings = LeadSettings(), preferArcs: Bool = true,
                lastPass: ProfileLastPass? = nil) {
        self.depth = depth; self.side = side; self.direction = direction; self.allowance = allowance
        self.tabs = tabs; self.ramp = ramp; self.lead = lead; self.preferArcs = preferArcs
        self.lastPass = lastPass
    }
}

public enum PocketStrategy: Codable, Hashable, Sendable {
    /// Successive inward offsets (contour-parallel).
    case offset
    /// Parallel zig-zag lines at `angle` degrees, with an optional final profile pass.
    case raster(angle: Double, profilePass: Bool)
}

public struct PocketParameters: Codable, Hashable, Sendable {
    public var depth: DepthSettings
    public var strategy: PocketStrategy
    public var direction: CutDirection
    public var allowance: Double
    /// Optional larger tool used first to clear the bulk; primary tool then cleans up.
    public var clearanceToolID: UUID?
    public var ramp: RampSettings
    /// Several clearance tools, cut in list order (largest first); each one only machines what the
    /// previous tools could not reach. When non-nil it replaces `clearanceToolID` (toolpaths-2d).
    public var clearanceToolIDs: [UUID]?
    /// Raster with a profile pass: cut the wall pass before the raster instead of after it
    /// (nil/false = after; toolpaths-2d addition).
    public var profilePassFirst: Bool?

    public init(depth: DepthSettings = DepthSettings(cutDepth: 0.25), strategy: PocketStrategy = .offset,
                direction: CutDirection = .climb, allowance: Double = 0, clearanceToolID: UUID? = nil,
                ramp: RampSettings = RampSettings(), clearanceToolIDs: [UUID]? = nil) {
        self.depth = depth; self.strategy = strategy; self.direction = direction; self.allowance = allowance
        self.clearanceToolID = clearanceToolID; self.ramp = ramp; self.clearanceToolIDs = clearanceToolIDs
    }

    /// The clearance tools in cutting order (the list, or the single legacy tool).
    public var clearanceTools: [UUID] { clearanceToolIDs ?? clearanceToolID.map { [$0] } ?? [] }
}

public struct DrillParameters: Codable, Hashable, Sendable {
    public var startDepth: Double
    public var cutDepth: Double
    /// Peck increment; 0 = single plunge.
    public var peckDepth: Double
    /// Height above the material top to retract to between pecks.
    public var retractHeight: Double
    public var dwellSeconds: Double

    public init(startDepth: Double = 0, cutDepth: Double = 0.5, peckDepth: Double = 0.125,
                retractHeight: Double = 0.05, dwellSeconds: Double = 0) {
        self.startDepth = startDepth; self.cutDepth = cutDepth; self.peckDepth = peckDepth
        self.retractHeight = retractHeight; self.dwellSeconds = dwellSeconds
    }
}

public enum FluteRamp: String, Codable, CaseIterable, Sendable {
    /// Ramp in at the start only.
    case start
    /// Ramp out at the end only.
    case end
    /// Ramp at both ends (classic fluting).
    case both
}

public struct FlutingParameters: Codable, Hashable, Sendable {
    public var depth: DepthSettings
    public var ramp: FluteRamp
    /// Ramp length as a fraction (0...0.5) of each vector's length.
    public var rampFraction: Double
    public var smoothRamp: Bool

    public init(depth: DepthSettings = DepthSettings(cutDepth: 0.25), ramp: FluteRamp = .both,
                rampFraction: Double = 0.25, smoothRamp: Bool = true) {
        self.depth = depth; self.ramp = ramp; self.rampFraction = rampFraction; self.smoothRamp = smoothRamp
    }
}

public struct TextureParameters: Codable, Hashable, Sendable {
    public var maxDepth: Double
    /// Stroke spacing across the texture direction.
    public var spacing: Double
    public var minStrokeLength: Double
    public var maxStrokeLength: Double
    /// Texture direction in degrees.
    public var angle: Double
    /// 0...1 randomness of depth/length/position.
    public var variation: Double
    public var seed: UInt64

    public init(maxDepth: Double = 0.06, spacing: Double = 0.15, minStrokeLength: Double = 0.5,
                maxStrokeLength: Double = 2.0, angle: Double = 0, variation: Double = 0.5, seed: UInt64 = 1) {
        self.maxDepth = maxDepth; self.spacing = spacing; self.minStrokeLength = minStrokeLength
        self.maxStrokeLength = maxStrokeLength; self.angle = angle; self.variation = variation; self.seed = seed
    }
}
