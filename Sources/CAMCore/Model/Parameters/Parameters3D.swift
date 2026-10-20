import CADCore
import Foundation

public struct Relief3DParameters: Codable, Hashable, Sendable {
    /// `Document.models` entry to machine.
    public var modelID: UUID
    /// Heightmap cell size (document units).
    public var resolution: Double
    public var roughing: RoughingSettings
    public var finishing: FinishingSettings
    /// Optional boundary vectors limiting the machined area (empty = model bounds + tool radius).
    public var boundaryShapeIDs: [UUID]
    /// Further models combined with `modelID` into one composite surface (the shallowest model
    /// wins where they overlap). nil/empty = machine `modelID` alone.
    public var additionalModelIDs: [UUID]?
    /// Two-sided machining (which side this operation cuts); nil = single-sided.
    public var twoSided: TwoSidedSettings?

    public init(modelID: UUID, resolution: Double = 0.01, roughing: RoughingSettings = RoughingSettings(),
                finishing: FinishingSettings = FinishingSettings(), boundaryShapeIDs: [UUID] = []) {
        self.modelID = modelID; self.resolution = resolution; self.roughing = roughing
        self.finishing = finishing; self.boundaryShapeIDs = boundaryShapeIDs
    }

    /// Primary model first, then the combined ones (duplicates removed).
    public var allModelIDs: [UUID] {
        var seen: Set<UUID> = [modelID]
        return [modelID] + (additionalModelIDs ?? []).filter { seen.insert($0).inserted }
    }
}

/// Z-level roughing with a flat end mill.
public struct RoughingSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Roughing tool; nil = use the operation's primary tool.
    public var toolID: UUID?
    /// Material left on the model for finishing.
    public var allowance: Double
    public var passDepth: Double?
    public var strategy: PocketStrategy

    public init(isEnabled: Bool = true, toolID: UUID? = nil, allowance: Double = 0.02, passDepth: Double? = nil,
                strategy: PocketStrategy = .raster(angle: 0, profilePass: false)) {
        self.isEnabled = isEnabled; self.toolID = toolID; self.allowance = allowance; self.passDepth = passDepth
        self.strategy = strategy
    }
}

/// Pattern of 3D finishing passes.
public enum FinishingStrategy: String, Codable, CaseIterable, Sendable {
    /// Parallel lines at `FinishingSettings.angle`.
    case raster
    /// Contour-parallel rings from the boundary inwards.
    case offset
    /// One continuous spiral from the boundary inwards (rings where the area splits).
    case spiral
}

/// Finishing with the operation's primary tool (ball / flat / V).
public struct FinishingSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Stepover; nil = the tool's stepover.
    public var stepover: Double?
    /// Raster angle in degrees.
    public var angle: Double
    /// Pass pattern; nil = raster (files from before strategies existed).
    public var strategy: FinishingStrategy?
    /// Rest machining: the larger tool that already finished this surface. When set, only the
    /// areas that tool could not reach are machined. nil = the whole area.
    public var restToolID: UUID?

    public init(isEnabled: Bool = true, stepover: Double? = nil, angle: Double = 0,
                strategy: FinishingStrategy? = nil) {
        self.isEnabled = isEnabled; self.stepover = stepover; self.angle = angle; self.strategy = strategy
    }
}

/// Two-sided 3D machining: the model is cut from the top down to `splitDepth`, then the board is
/// flipped and the underside is cut from the new top down to the split plane, leaving `web`.
public struct TwoSidedSettings: Codable, Hashable, Sendable {
    public enum Side: String, Codable, CaseIterable, Sendable {
        /// First side, as placed (material top up).
        case top
        /// Second side, after flipping the board.
        case bottom
    }

    /// How the board is turned over between the sides.
    public enum Flip: String, Codable, CaseIterable, Sendable {
        /// Turned over around its vertical centre line (X mirrored).
        case leftRight
        /// Turned over around its horizontal centre line (Y mirrored).
        case topBottom
    }

    public var side: Side
    public var flip: Flip
    /// Depth below the (first side's) material top of the plane that separates the two sides;
    /// nil = halfway between the model's top and bottom.
    public var splitDepth: Double?
    /// Material left between the two sides at the split plane around the model, so the part stays
    /// attached to the board (trim it off afterwards). 0 = the sides meet.
    public var web: Double

    public init(side: Side = .top, flip: Flip = .leftRight, splitDepth: Double? = nil, web: Double = 0.04) {
        self.side = side; self.flip = flip; self.splitDepth = splitDepth; self.web = web
    }
}
