import CADCore
import Foundation

/// Data-driven post-processor definition (serialisable to JSON) so new machines can be added
/// without code. Template placeholders:
///   {T} tool number, {TOOL_NAME}, {S} spindle RPM, {SECONDS} dwell, {SAFE_Z}, {HOME_X}, {HOME_Y},
///   {HOME_Z}, {JOB_NAME}, {POST_NAME}, {POST_VERSION}
/// Numeric placeholders are formatted with `decimals`.
public struct PostProfile: Codable, Hashable, Identifiable, Sendable {
    public enum CommentStyle: String, Codable, Sendable { case parentheses, semicolon }
    public enum ArcOutput: String, Codable, Sendable {
        /// G2/G3 with I J relative to the arc start (Mach default, GRBL).
        case incrementalIJ
        /// G2/G3 with absolute I J centre.
        case absoluteIJ
        /// No arcs: linearize with `arcTolerance`.
        case linearize
    }

    public var id: String
    public var name: String
    public var version: String
    public var fileExtension: String
    /// Output units; toolpaths are scaled from document units if different.
    public var units: LengthUnit
    public var commentStyle: CommentStyle
    public var lineNumbers: Bool
    /// Coordinate decimals (4 for inch, 3 for mm is typical).
    public var decimals: Int
    public var feedDecimals: Int
    /// Emit the header comment block (job, tools, material, Z zero, post version).
    public var headerComments: Bool
    /// Modal setup after the units code (G20/G21 is emitted automatically before these).
    public var preamble: [String]
    /// Lines emitted at every tool change (including the first tool).
    public var toolChange: [String]
    /// When true, `toolLengthOffset` is emitted after the tool change.
    public var useToolLengthOffset: Bool
    public var toolLengthOffset: String
    public var spindleOn: String
    /// Dwell after spindle start, seconds (0 = none).
    public var spindleDwellSeconds: Double
    public var dwell: String
    public var spindleOff: String
    public var minRPM: Double
    public var maxRPM: Double
    public var rapid: String
    public var linear: String
    public var arcCW: String
    public var arcCCW: String
    public var arcOutput: ArcOutput
    /// Chordal tolerance for linearized arcs, in output units.
    public var arcTolerance: Double
    /// Allow helical arcs (Z change during G2/G3); otherwise helices are linearized.
    public var helicalArcs: Bool
    /// Omit repeated G-words/feeds when unchanged.
    public var modal: Bool
    public var footer: [String]
    public var limits: MachineLimits
    /// Rapid traverse speed in output units per minute (for time estimates).
    public var rapidRate: Double
    public var maxFeed: Double

    public init(id: String, name: String, version: String = "1.0", fileExtension: String = "tap",
                units: LengthUnit, commentStyle: CommentStyle = .parentheses, lineNumbers: Bool = false,
                decimals: Int, feedDecimals: Int = 1, headerComments: Bool = true,
                preamble: [String], toolChange: [String], useToolLengthOffset: Bool = false,
                toolLengthOffset: String = "G43 H{T}", spindleOn: String = "M3 S{S}",
                spindleDwellSeconds: Double = 3, dwell: String = "G4 P{SECONDS}", spindleOff: String = "M5",
                minRPM: Double, maxRPM: Double, rapid: String = "G0", linear: String = "G1",
                arcCW: String = "G2", arcCCW: String = "G3", arcOutput: ArcOutput = .incrementalIJ,
                arcTolerance: Double, helicalArcs: Bool = true, modal: Bool = true, footer: [String],
                limits: MachineLimits, rapidRate: Double, maxFeed: Double) {
        self.id = id; self.name = name; self.version = version; self.fileExtension = fileExtension
        self.units = units; self.commentStyle = commentStyle; self.lineNumbers = lineNumbers
        self.decimals = decimals; self.feedDecimals = feedDecimals; self.headerComments = headerComments
        self.preamble = preamble; self.toolChange = toolChange; self.useToolLengthOffset = useToolLengthOffset
        self.toolLengthOffset = toolLengthOffset; self.spindleOn = spindleOn
        self.spindleDwellSeconds = spindleDwellSeconds; self.dwell = dwell; self.spindleOff = spindleOff
        self.minRPM = minRPM; self.maxRPM = maxRPM; self.rapid = rapid; self.linear = linear
        self.arcCW = arcCW; self.arcCCW = arcCCW; self.arcOutput = arcOutput; self.arcTolerance = arcTolerance
        self.helicalArcs = helicalArcs; self.modal = modal; self.footer = footer; self.limits = limits
        self.rapidRate = rapidRate; self.maxFeed = maxFeed
    }

    /// "G20" or "G21".
    public var unitsCode: String { units == .inch ? "G20" : "G21" }

    public func comment(_ text: String) -> String {
        let text = Self.asciiOnly(text)
        switch commentStyle {
        case .parentheses:
            // Parentheses cannot nest in G-code comments.
            let clean = text.replacingOccurrences(of: "(", with: "[").replacingOccurrences(of: ")", with: "]")
            return "( \(clean) )"
        case .semicolon:
            return "; \(text)"
        }
    }

    /// Controllers vary in how they treat non-ASCII bytes; keep comments plain ASCII.
    public static func asciiOnly(_ text: String) -> String {
        let replaced = text.replacingOccurrences(of: "°", with: " deg")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
        let stripped = replaced.applyingTransform(.stripDiacritics, reverse: false) ?? replaced
        return String(stripped.unicodeScalars.filter { $0.isASCII }.map(Character.init))
    }

    public func toJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public static func fromJSON(_ data: Data) throws -> PostProfile {
        try JSONDecoder().decode(PostProfile.self, from: data)
    }
}

/// Machine travel envelope in the profile's units.
public struct MachineLimits: Codable, Hashable, Sendable {
    public var xTravel: Double
    public var yTravel: Double
    public var zTravel: Double
    /// Max allowed cut below the spoilboard surface (into the spoilboard), positive value.
    public var maxSpoilboardCut: Double

    public init(xTravel: Double, yTravel: Double, zTravel: Double, maxSpoilboardCut: Double) {
        self.xTravel = xTravel; self.yTravel = yTravel; self.zTravel = zTravel
        self.maxSpoilboardCut = maxSpoilboardCut
    }
}
