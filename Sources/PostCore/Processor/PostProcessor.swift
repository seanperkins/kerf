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
        try ProgramBuilder(profile: profile, job: job).build()
    }

    /// Combined export: toolpaths grouped by tool (first-appearance order) so each tool is
    /// loaded once, then posted as one program.
    public func postCombined(_ job: PostJob) throws -> String {
        var grouped = job
        grouped.toolpaths = ToolpathOrdering.groupedByTool(job.toolpaths)
        return try post(grouped)
    }

    /// Suggested file name for a program: "<job name>.<profile extension>".
    public func fileName(for jobName: String) -> String {
        let base = jobName.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled" : jobName
        return base + "." + profile.fileExtension
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
