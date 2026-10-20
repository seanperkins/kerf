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

    public init(modelID: UUID, resolution: Double = 0.01, roughing: RoughingSettings = RoughingSettings(),
                finishing: FinishingSettings = FinishingSettings(), boundaryShapeIDs: [UUID] = []) {
        self.modelID = modelID; self.resolution = resolution; self.roughing = roughing
        self.finishing = finishing; self.boundaryShapeIDs = boundaryShapeIDs
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

/// Raster finishing with the operation's primary tool (ball / flat / V).
public struct FinishingSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Stepover; nil = the tool's stepover.
    public var stepover: Double?
    /// Raster angle in degrees.
    public var angle: Double

    public init(isEnabled: Bool = true, stepover: Double? = nil, angle: Double = 0) {
        self.isEnabled = isEnabled; self.stepover = stepover; self.angle = angle
    }
}
