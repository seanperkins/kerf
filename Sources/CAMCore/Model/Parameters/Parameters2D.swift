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

    public init(isEnabled: Bool = false, length: Double = 0.25, thickness: Double = 0.125,
                countPerPath: Int = 4, isTriangular: Bool = false, spacing: Double? = nil) {
        self.isEnabled = isEnabled; self.length = length; self.thickness = thickness
        self.countPerPath = countPerPath; self.isTriangular = isTriangular; self.spacing = spacing
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

    public init(depth: DepthSettings = DepthSettings(cutDepth: 0.75), side: ProfileSide = .outside,
                direction: CutDirection = .climb, allowance: Double = 0, tabs: TabSettings = TabSettings(),
                ramp: RampSettings = RampSettings(), lead: LeadSettings = LeadSettings(), preferArcs: Bool = true) {
        self.depth = depth; self.side = side; self.direction = direction; self.allowance = allowance
        self.tabs = tabs; self.ramp = ramp; self.lead = lead; self.preferArcs = preferArcs
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

    public init(depth: DepthSettings = DepthSettings(cutDepth: 0.25), strategy: PocketStrategy = .offset,
                direction: CutDirection = .climb, allowance: Double = 0, clearanceToolID: UUID? = nil,
                ramp: RampSettings = RampSettings()) {
        self.depth = depth; self.strategy = strategy; self.direction = direction; self.allowance = allowance
        self.clearanceToolID = clearanceToolID; self.ramp = ramp
    }
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
