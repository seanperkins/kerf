import CADCore
import Foundation

public struct VCarveParameters: Codable, Hashable, Sendable {
    public var startDepth: Double
    /// Max carve depth; nil = unlimited (pure V, depth set by the medial axis).
    public var flatDepth: Double?
    /// Optional flat tool to clear areas bottomed out at `flatDepth`.
    public var flatClearanceToolID: UUID?
    public var flatClearanceStrategy: PocketStrategy
    /// Max stepdown for very deep V-cuts (nil = single pass).
    public var passDepth: Double?

    public init(startDepth: Double = 0, flatDepth: Double? = nil, flatClearanceToolID: UUID? = nil,
                flatClearanceStrategy: PocketStrategy = .offset, passDepth: Double? = nil) {
        self.startDepth = startDepth; self.flatDepth = flatDepth; self.flatClearanceToolID = flatClearanceToolID
        self.flatClearanceStrategy = flatClearanceStrategy; self.passDepth = passDepth
    }
}

public enum InlayPart: String, Codable, CaseIterable, Sendable { case female, male, both }

/// V-carve inlay pair. Female (pocket) is a flat-bottom V-carve to `pocketDepth`;
/// male (plug) is a mirrored V-carve cut from `maleStartDepth` down with `glueGap`.
public struct InlayParameters: Codable, Hashable, Sendable {
    public var part: InlayPart
    public var pocketDepth: Double
    /// Male V-carve starts this far ABOVE the female's surface reference (VCarve "start depth").
    public var maleStartDepth: Double
    /// Gap left at the bottom between plug and pocket for glue.
    public var glueGap: Double
    public var flatClearanceToolID: UUID?
    /// Mirror the male part horizontally (normally true).
    public var mirrorMale: Bool
    /// Clear the waste around the male part (extra distance outside the vectors).
    public var maleBoundaryMargin: Double

    public init(part: InlayPart = .both, pocketDepth: Double = 0.2, maleStartDepth: Double = 0.1,
                glueGap: Double = 0.02, flatClearanceToolID: UUID? = nil, mirrorMale: Bool = true,
                maleBoundaryMargin: Double = 0.25) {
        self.part = part; self.pocketDepth = pocketDepth; self.maleStartDepth = maleStartDepth
        self.glueGap = glueGap; self.flatClearanceToolID = flatClearanceToolID; self.mirrorMale = mirrorMale
        self.maleBoundaryMargin = maleBoundaryMargin
    }
}
