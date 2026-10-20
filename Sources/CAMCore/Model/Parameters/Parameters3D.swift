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

    public init(isEnabled: Bool = true, stepover: Double? = nil, angle: Double = 0,
                strategy: FinishingStrategy? = nil) {
        self.isEnabled = isEnabled; self.stepover = stepover; self.angle = angle; self.strategy = strategy
    }
}
