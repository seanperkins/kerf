import CADCore
import CAMCore
import Foundation

public struct GCodeIssue: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Hashable, Sendable { case warning, error }
    public var severity: Severity
    /// 1-based line number in the G-code, when applicable.
    public var line: Int?
    public var message: String

    public init(severity: Severity, line: Int? = nil, message: String) {
        self.severity = severity; self.line = line; self.message = message
    }

    public var description: String {
        "\(severity.rawValue)\(line.map { " line \($0)" } ?? ""): \(message)"
    }
}

/// Safety checks on toolpaths / generated G-code: travel limits, cut depth vs. material
/// bottom and spoilboard, rapids below safe Z, RPM range, missing tool changes.
public struct GCodeValidator: Sendable {
    public var profile: PostProfile
    public var job: JobSetup
    public var units: LengthUnit

    public init(profile: PostProfile, job: JobSetup, units: LengthUnit) {
        self.profile = profile; self.job = job; self.units = units
    }

    public func validate(toolpaths: [Toolpath]) -> [GCodeIssue] {
        // TODO(post): implement.
        []
    }

    public func validate(gcode: String) -> [GCodeIssue] {
        // TODO(post): parse G0/G1/G2/G3 + Z; check limits and rapids at/above safe Z.
        []
    }
}
