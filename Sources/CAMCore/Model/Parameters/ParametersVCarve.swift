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
    /// Further flat-area clearance tools, run in list order after `flatClearanceToolID`; each one
    /// only machines what the tools before it could not reach.
    public var extraClearanceTools: [VCarveClearanceTool]
    /// Engrave selected open vectors with the V-bit this deep below `startDepth`
    /// (nil = open vectors are ignored with a warning).
    public var openVectorDepth: Double?
    /// Fraction of each open vector's length (0…0.5) over which its ends rise smoothly to the
    /// surface, for tapered sketch-style strokes (0 = constant depth).
    public var openVectorTaper: Double

    public init(startDepth: Double = 0, flatDepth: Double? = nil, flatClearanceToolID: UUID? = nil,
                flatClearanceStrategy: PocketStrategy = .offset, passDepth: Double? = nil,
                extraClearanceTools: [VCarveClearanceTool] = [], openVectorDepth: Double? = nil,
                openVectorTaper: Double = 0) {
        self.startDepth = startDepth; self.flatDepth = flatDepth; self.flatClearanceToolID = flatClearanceToolID
        self.flatClearanceStrategy = flatClearanceStrategy; self.passDepth = passDepth
        self.extraClearanceTools = extraClearanceTools
        self.openVectorDepth = openVectorDepth; self.openVectorTaper = openVectorTaper
    }

    /// Every flat-area clearance tool in cutting order (empty without a flat depth tool).
    public var clearanceTools: [VCarveClearanceTool] {
        guard let first = flatClearanceToolID else { return [] }
        return [VCarveClearanceTool(toolID: first)] + extraClearanceTools
    }
}

extension VCarveParameters {
    // Decoder written out so fields added after format 1 default when missing.
    private enum CodingKeys: String, CodingKey {
        case startDepth, flatDepth, flatClearanceToolID, flatClearanceStrategy, passDepth, extraClearanceTools
        case openVectorDepth, openVectorTaper
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(startDepth: try c.decode(Double.self, forKey: .startDepth),
                  flatDepth: try c.decodeIfPresent(Double.self, forKey: .flatDepth),
                  flatClearanceToolID: try c.decodeIfPresent(UUID.self, forKey: .flatClearanceToolID),
                  flatClearanceStrategy: try c.decode(PocketStrategy.self, forKey: .flatClearanceStrategy),
                  passDepth: try c.decodeIfPresent(Double.self, forKey: .passDepth),
                  extraClearanceTools: try c.decodeIfPresent([VCarveClearanceTool].self, forKey: .extraClearanceTools) ?? [],
                  openVectorDepth: try c.decodeIfPresent(Double.self, forKey: .openVectorDepth),
                  openVectorTaper: try c.decodeIfPresent(Double.self, forKey: .openVectorTaper) ?? 0)
    }
}

/// A flat-area clearance tool after the first one.
public struct VCarveClearanceTool: Codable, Hashable, Sendable {
    public var toolID: UUID
    /// Corner sharpening (tapered engraving / V tools only): after clearing what it can at the
    /// flat depth, the tool follows the medial axis into corners it could not reach, lifted so
    /// its tip fits without touching the carved walls.
    public var cornerSharpen: Bool

    public init(toolID: UUID, cornerSharpen: Bool = false) {
        self.toolID = toolID; self.cornerSharpen = cornerSharpen
    }

    private enum CodingKeys: String, CodingKey { case toolID, cornerSharpen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(toolID: try c.decode(UUID.self, forKey: .toolID),
                  cornerSharpen: try c.decodeIfPresent(Bool.self, forKey: .cornerSharpen) ?? false)
    }
}

public enum InlayPart: String, Codable, CaseIterable, Sendable { case female, male, both }

/// How far the plug's waste is cleared around the mirrored vectors.
public enum InlayPlugBoundary: String, Codable, CaseIterable, Sendable {
    /// The vectors' bounding box grown by `maleBoundaryMargin`.
    case boundaryOffset
    /// The vectors' own outline grown by `maleBoundaryMargin` (least material removed; the plug
    /// may need freeing from the board).
    case vectorOffset
    /// The whole material sheet.
    case sheetLimits
}

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
    /// Further flat-area clearance tools after `flatClearanceToolID` (rest machining, in order).
    public var extraClearanceTools: [VCarveClearanceTool]
    /// Outer limit of the plug's waste clearing.
    public var plugBoundary: InlayPlugBoundary
    /// Plug "surface clearance": how far the plug board's cleared floor stays above the pocket
    /// board's surface once seated (= the male carve's depth below its start depth).
    /// nil = pocket depth − plug start depth.
    public var surfaceClearance: Double?

    public init(part: InlayPart = .both, pocketDepth: Double = 0.2, maleStartDepth: Double = 0.1,
                glueGap: Double = 0.02, flatClearanceToolID: UUID? = nil, mirrorMale: Bool = true,
                maleBoundaryMargin: Double = 0.25, extraClearanceTools: [VCarveClearanceTool] = [],
                plugBoundary: InlayPlugBoundary = .boundaryOffset, surfaceClearance: Double? = nil) {
        self.part = part; self.pocketDepth = pocketDepth; self.maleStartDepth = maleStartDepth
        self.glueGap = glueGap; self.flatClearanceToolID = flatClearanceToolID; self.mirrorMale = mirrorMale
        self.maleBoundaryMargin = maleBoundaryMargin; self.extraClearanceTools = extraClearanceTools
        self.plugBoundary = plugBoundary; self.surfaceClearance = surfaceClearance
    }

    /// The plug's carve depth below its start depth (the effective surface clearance).
    public var effectiveSurfaceClearance: Double { surfaceClearance ?? (pocketDepth - maleStartDepth) }

    /// Every clearance tool ID in cutting order (empty without a first clearance tool).
    public var clearanceToolIDs: [UUID] {
        guard let first = flatClearanceToolID else { return [] }
        return [first] + extraClearanceTools.map(\.toolID)
    }
}

extension InlayParameters {
    private enum CodingKeys: String, CodingKey {
        case part, pocketDepth, maleStartDepth, glueGap, flatClearanceToolID, mirrorMale, maleBoundaryMargin
        case extraClearanceTools, plugBoundary, surfaceClearance
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(part: try c.decode(InlayPart.self, forKey: .part),
                  pocketDepth: try c.decode(Double.self, forKey: .pocketDepth),
                  maleStartDepth: try c.decode(Double.self, forKey: .maleStartDepth),
                  glueGap: try c.decode(Double.self, forKey: .glueGap),
                  flatClearanceToolID: try c.decodeIfPresent(UUID.self, forKey: .flatClearanceToolID),
                  mirrorMale: try c.decode(Bool.self, forKey: .mirrorMale),
                  maleBoundaryMargin: try c.decode(Double.self, forKey: .maleBoundaryMargin),
                  extraClearanceTools: try c.decodeIfPresent([VCarveClearanceTool].self, forKey: .extraClearanceTools) ?? [],
                  plugBoundary: try c.decodeIfPresent(InlayPlugBoundary.self, forKey: .plugBoundary) ?? .boundaryOffset,
                  surfaceClearance: try c.decodeIfPresent(Double.self, forKey: .surfaceClearance))
    }
}
