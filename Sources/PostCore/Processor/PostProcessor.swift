import CADCore
import CAMCore
import Foundation

public enum PostError: Error, Equatable, Sendable {
    case notImplemented(String)
    case noToolpaths
    case spindleSpeedOutOfRange(Double)
}

/// Everything needed to write one G-code file.
public struct PostJob: Sendable {
    public var name: String
    /// Units of the toolpaths (the document's units).
    public var units: LengthUnit
    public var job: JobSetup
    /// Toolpaths in output order. A tool change is emitted whenever the tool changes.
    public var toolpaths: [Toolpath]
    public var materialDescription: String?

    public init(name: String, units: LengthUnit, job: JobSetup, toolpaths: [Toolpath],
                materialDescription: String? = nil) {
        self.name = name; self.units = units; self.job = job; self.toolpaths = toolpaths
        self.materialDescription = materialDescription
    }
}

public protocol PostProcessor: Sendable {
    var profile: PostProfile { get }
    /// Full program text (header, tool changes, moves, footer), lines joined with "\n".
    func post(_ job: PostJob) throws -> String
}

/// The profile-driven post processor used for every shipped machine.
public struct TemplatePostProcessor: PostProcessor {
    public var profile: PostProfile

    public init(profile: PostProfile) { self.profile = profile }

    public func post(_ job: PostJob) throws -> String {
        // TODO(post): header block, units + preamble, tool changes, spindle, moves with
        // safe-Z enforcement, arcs per `profile.arcOutput`, footer.
        throw PostError.notImplemented("TemplatePostProcessor.post")
    }
}

public enum ToolpathOrdering {
    /// Combined export: stable-group toolpaths by tool (first appearance order) so each tool
    /// is loaded once.
    public static func groupedByTool(_ toolpaths: [Toolpath]) -> [Toolpath] {
        var order: [UUID] = []
        var groups: [UUID: [Toolpath]] = [:]
        for tp in toolpaths {
            if groups[tp.tool.id] == nil { order.append(tp.tool.id) }
            groups[tp.tool.id, default: []].append(tp)
        }
        return order.flatMap { groups[$0] ?? [] }
    }
}
