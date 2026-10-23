import CADCore
import CAMCore
import Foundation
import PostCore

/// Mistakes in a toolpath's settings that the export validator would only catch at the last step, shown in the
/// toolpath form as soon as they are made (issue #24): a cut deeper than the stock allows, a tool with no feed,
/// plunge or diameter, a tab as tall as the cut, a spindle speed the post cannot run. (A cut deeper than the
/// tool's flutes has its own note under the cut depth, `OperationHints.fluteLengthProblem`.)
enum OperationWarnings {
    /// The warnings for `op` as the form would show them. `library` is the library the document cuts with (the
    /// project's snapshot included), `profile` the post in force with the job's machine limits applied, `units`
    /// the document's.
    static func make(_ op: AnyOperation, project: KerfProject, library: ToolLibrary, profile: PostProfile,
                     units: LengthUnit) -> [String] {
        var out: [String] = []
        let job: JobSetup
        if case .success(let j) = project.machiningJob(for: op) { job = j } else { job = project.document.job }
        guard let stored = library.tool(id: op.setup.toolID) else { return out }
        var tool = stored.forMaterial(job.material).converted(to: units)
        if let o = op.setup.toolOverride { tool = o.applied(to: tool) }
        let u = units.abbreviation

        if op.kind != .merge {
            out += toolProblems(tool, profile: profile, overridable: true)
            // The other tools the operation cuts with (clearance, roughing, rest) are judged the same way, by name.
            var seen: Set<UUID> = [op.setup.toolID]
            for id in secondaryToolIDs(of: op) where seen.insert(id).inserted {
                guard let other = library.tool(id: id)?.forMaterial(job.material).converted(to: units) else { continue }
                out += toolProblems(other, profile: profile, overridable: false).map { "\(other.name): \($0)" }
            }
        }

        if let depth = cutDepth(of: op, tool: tool), op.setup.projectOntoModelID == nil {
            // The validator's rule: the material bottom plus what the machine lets a cut into the spoilboard.
            let allowed = job.thickness + max(0, profile.limits.maxSpoilboardCut) * profile.units.factor(to: units)
            if depth > allowed + CAMContext.defaultTolerance(units) {
                let past = RulerTicks.label(((depth - job.thickness) * 10000).rounded() / 10000)
                out.append("The cut is \(past) \(u) below the material bottom (\(RulerTicks.label(job.thickness)) \(u) thick); "
                           + "the machine allows \(RulerTicks.label(allowed - job.thickness)) \(u) into the spoilboard.")
            }
        }

        if case .profile(let p) = op, p.params.tabs.isEnabled {
            let span = p.params.depth.cutDepth - p.params.depth.startDepth
            if p.params.tabs.thickness >= span - CAMContext.defaultTolerance(units), span > 0 {
                out.append("The tabs (\(RulerTicks.label(p.params.tabs.thickness)) \(u) tall) are as tall as the cut "
                           + "(\(RulerTicks.label(span)) \(u) deep): nothing is cut through between them.")
            }
        }
        return out
    }

    /// What is wrong with a tool's own numbers: diameter, feed, plunge and spindle speed. Only the toolpath's
    /// primary tool can be fixed with the toolpath's override, so only its messages say so.
    static func toolProblems(_ tool: Tool, profile: PostProfile, overridable: Bool) -> [String] {
        var out: [String] = []
        let fix = overridable ? "set it in the Tool Database or override it here" : "set it in the Tool Database"
        if !(tool.diameter > 0) { out.append("The tool's diameter is not above zero; set it in the Tool Database.") }
        if !(tool.feedRate > 0) { out.append("The feed rate is zero or less; \(fix).") }
        if !(tool.plungeRate > 0) { out.append("The plunge rate is zero or less; \(fix).") }
        if let rpm = rpmProblem(tool.spindleRPM, profile: profile) { out.append(rpm) }
        return out
    }

    /// The tools besides the primary one that the operation cuts with, in the order it uses them: a pocket's and a
    /// V-carve's or inlay's flat-area clearance tools, a relief's roughing and rest tools.
    static func secondaryToolIDs(of op: AnyOperation) -> [UUID] {
        switch op {
        case .pocket(let o): return o.params.clearanceTools
        case .vcarve(let o): return o.params.clearanceTools.map(\.toolID)
        case .inlay(let o): return o.params.clearanceToolIDs
        case .relief3D(let o):
            return (o.params.roughing.isEnabled ? o.params.roughing.toolID.map { [$0] } ?? [] : [])
                + (o.params.finishing.restToolID.map { [$0] } ?? [])
        default: return []
        }
    }

    /// Why `rpm` is outside what `profile`'s spindle runs, or nil. The range is the post's, not a constant.
    static func rpmProblem(_ rpm: Double, profile: PostProfile) -> String? {
        guard !(rpm >= profile.minRPM && rpm <= profile.maxRPM) else { return nil }
        let range = "\(RulerTicks.label(profile.minRPM))–\(RulerTicks.label(profile.maxRPM)) RPM"
        return "The spindle speed \(RulerTicks.label(rpm)) RPM is outside the range \(range) of the post \(profile.name)."
    }

    /// The deepest the operation's own settings cut below the material top, for the kinds with a single cut depth.
    static func cutDepth(of op: AnyOperation, tool: Tool) -> Double? {
        switch op {
        case .profile(let o): return o.params.depth.cutDepth
        case .pocket(let o): return o.params.depth.cutDepth
        case .fluting(let o): return o.params.depth.cutDepth
        case .engrave(let o): return o.params.depth.cutDepth
        case .drill(let o): return o.params.cutDepth
        case .holeMill(let o): return o.params.cutDepth
        case .chamfer(let o): return (try? ChamferOperation.size(tool: tool, params: o.params))?.tipDepth
        default: return nil
        }
    }
}
