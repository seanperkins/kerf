import CADCore
import CAMCore
import Foundation
import PostCore

/// What to write into one G-code file.
enum GCodeExportScope: Hashable {
    /// All enabled, calculated toolpaths.
    case all
    /// A single operation's toolpaths.
    case operation(UUID)
}

struct GCodeExportResult {
    var text: String?
    var issues: [GCodeIssue]
    var errorMessage: String?
    var toolpathCount: Int

    var hasErrors: Bool { issues.contains { $0.severity == .error } }
}

/// Collects toolpaths, runs the post processor and the validator. Pure (no UI).
enum GCodeExporter {
    /// UserDefaults key for the shared "group by tool" choice. The export, validation and
    /// tool-change summary panels and the 3D preview all read it, so the simulated order is
    /// always the exported order. Off by default: the user's toolpath order is kept.
    static let groupByToolKey = "kerf.groupByTool"
    static func toolpaths(scope: GCodeExportScope, operations: [AnyOperation],
                          results: [UUID: ToolpathResult], groupByTool: Bool) -> [Toolpath] {
        switch scope {
        case .operation(let id):
            return results[id]?.toolpaths ?? []
        case .all:
            let tps = operations.filter(\.setup.isEnabled).flatMap { results[$0.id]?.toolpaths ?? [] }
            return groupByTool ? ToolpathOrdering.groupedByTool(tps) : tps
        }
    }

    /// Errors for toolpaths that come over a keep-out zone below its top (+ clearance margin).
    static func keepOutIssues(_ toolpaths: [Toolpath], document doc: Document) -> [GCodeIssue] {
        guard let zones = doc.keepOutZones, !zones.isEmpty else { return [] }
        let margin = doc.units == .inch ? 0.05 : 1.0
        let tol = doc.units == .inch ? 0.0005 : 0.01
        return KeepOut.violations(toolpaths, zones: zones, coords: MachineCoordinates(job: doc.job), margin: margin,
                                  tolerance: tol).map { v in
            let what = v.isRapid ? "rapids over" : "cuts into"
            return GCodeIssue(severity: .error, message: "\(v.toolpathName) \(what) keep-out zone \"\(v.zoneName)\" near X\(RulerTicks.label((v.at.x * 1000).rounded() / 1000)) Y\(RulerTicks.label((v.at.y * 1000).rounded() / 1000))")
        }
    }

    /// Raises the post's travel between toolpaths over "lift over" keep-out zones.
    static func linkOverKeepOutZones(_ toolpaths: [Toolpath], document doc: Document) -> [Toolpath] {
        guard let zones = doc.keepOutZones, zones.contains(where: { $0.liftOver == true }) else { return toolpaths }
        let margin = doc.units == .inch ? 0.05 : 1.0
        let tol = doc.units == .inch ? 0.0005 : 0.01
        return KeepOutAvoidance.link(toolpaths, zones: zones, coords: MachineCoordinates(job: doc.job), margin: margin,
                                     tolerance: tol)
    }

    static func materialDescription(_ doc: Document) -> String {
        let j = doc.job
        func f(_ v: Double) -> String { RulerTicks.label(v) }
        return "\(f(j.width)) x \(f(j.height)) x \(f(j.thickness)) \(doc.units.abbreviation)"
    }

    static func export(project: KerfProject, toolpaths: [Toolpath], profile: PostProfile,
                       jobName: String) -> GCodeExportResult {
        let doc = project.document
        guard !toolpaths.isEmpty else {
            return GCodeExportResult(text: nil, issues: [], errorMessage: "There are no calculated toolpaths to export.",
                                     toolpathCount: 0)
        }
        // Travel between toolpaths crosses lift-over zones at safe Z unless raised here: each
        // operation was re-routed on its own, so only the final order shows these moves.
        let toolpaths = linkOverKeepOutZones(toolpaths, document: doc)
        let validator = GCodeValidator(profile: profile, job: doc.job, units: doc.units)
        var issues = validator.validate(toolpaths: toolpaths)
        issues += keepOutIssues(toolpaths, document: doc)
        issues += LayoutChecks.toolpaths(toolpaths, job: doc.job, units: doc.units)
        issues += LayoutChecks.keepOut(toolpaths, zones: Fixtures.zones(in: doc), job: doc.job, units: doc.units)
        // The post header already prints W x H x T, so no extra material description.
        let job = PostJob(name: jobName, units: doc.units, job: doc.job, toolpaths: toolpaths)
        do {
            let text = try TemplatePostProcessor(profile: profile).post(job)
            issues += validator.validate(gcode: text)
            return GCodeExportResult(text: text, issues: issues, errorMessage: nil, toolpathCount: toolpaths.count)
        } catch PostError.notImplemented(let what) {
            return GCodeExportResult(text: nil, issues: issues,
                                     errorMessage: "\(what) is not available in this build yet.",
                                     toolpathCount: toolpaths.count)
        } catch PostError.spindleSpeedOutOfRange(let rpm) {
            return GCodeExportResult(text: nil, issues: issues,
                                     errorMessage: "Spindle speed \(Int(rpm)) RPM is outside the machine's range (\(Int(profile.minRPM))–\(Int(profile.maxRPM))).",
                                     toolpathCount: toolpaths.count)
        } catch {
            return GCodeExportResult(text: nil, issues: issues, errorMessage: "\(error)", toolpathCount: toolpaths.count)
        }
    }

    /// File name like "Sign_Profile_1.tap" (unsafe characters replaced).
    static func suggestedFileName(jobName: String, operationName: String?, profile: PostProfile) -> String {
        var base = jobName.isEmpty ? "Untitled" : jobName
        if let op = operationName { base += "_" + op }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let clean = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return clean + "." + profile.fileExtension
    }
}
