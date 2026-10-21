import CADCore
import CAMCore
import Foundation
import PostCore

/// Per-toolpath times and the tool-change sequence of a combined export (sidebar summary and
/// the "Save All Toolpaths" sheet). Pure: built from operations and their results.
struct JobSummary: Equatable {
    struct Row: Equatable, Identifiable {
        var id: UUID
        var name: String
        var kind: OperationKind
        /// "T1 · 1/4" End Mill" for each distinct tool the operation's toolpaths use, in order.
        var tools: [String]
        /// nil until calculated (or when the calculation failed).
        var estimatedSeconds: TimeInterval?
        var isEnabled: Bool
        var error: String?
    }

    /// One tool load in the combined program.
    struct ToolLoad: Equatable {
        var number: Int
        var name: String
        var toolpathNames: [String]
    }

    /// An operator pause between two toolpaths.
    struct PauseRow: Equatable {
        var after: String
        var text: String
    }

    var rows: [Row]
    /// Tool loads (each is a manual tool change at the machine) in program order.
    var sequence: [ToolLoad]
    /// Operator pauses in program order (the last toolpath's pause is never written).
    var pauses: [PauseRow] = []
    /// Stops at the machine: tool changes plus pauses, a pause that ends in a tool change counted once.
    var stops: Int = 0
    /// Cutting, rapids and dwell of the enabled toolpaths, summed one by one. No tool-change
    /// allowance, not even for a change inside one operation: those are all in `toolChangeAllowance`.
    var machiningSeconds: TimeInterval
    /// Allowance for one manual tool change (the user's time-estimate setting).
    var toolChangeSeconds: TimeInterval = 0

    /// False until at least one enabled toolpath has been calculated; a total of 0s then means
    /// "not calculated", not "instant".
    var hasEstimate: Bool { rows.contains { $0.isEnabled && $0.estimatedSeconds != nil } }

    /// Changes after the first tool is loaded.
    var toolChanges: Int { max(0, sequence.count - 1) }
    /// What the stops add: the same allowance the 3D preview counts, so the sidebar and the
    /// preview agree instead of showing two different times for one job.
    var toolChangeAllowance: TimeInterval { Double(stops) * toolChangeSeconds }
    var totalSeconds: TimeInterval { machiningSeconds + toolChangeAllowance }

    static func label(_ tool: Tool) -> String { "T\(tool.number) · \(tool.name)" }

    static func make(operations: [AnyOperation], results: [UUID: ToolpathResult], groupByTool: Bool,
                     toolChangeSeconds: TimeInterval = 0) -> JobSummary {
        let rows = operations.map { op -> Row in
            let r = results[op.id]
            var tools: [String] = []
            for tp in r?.toolpaths ?? [] where !tools.contains(label(tp.tool)) { tools.append(label(tp.tool)) }
            let ok = r.map { $0.error == nil } ?? false
            return Row(id: op.id, name: op.setup.name, kind: op.kind, tools: tools,
                       estimatedSeconds: ok ? r?.estimatedSeconds : nil, isEnabled: op.setup.isEnabled,
                       error: r?.error)
        }
        let tps = GCodeExporter.toolpaths(scope: .all, operations: operations, results: results, groupByTool: groupByTool)
        // A row's own time includes the tool changes inside its operation (a pocket's clearance
        // tool, a V-carve's flat-area tool); the job total counts every stop once, below.
        let total = operations.filter(\.setup.isEnabled).compactMap { op -> TimeInterval? in
            guard let r = results[op.id], r.error == nil else { return nil }
            return r.machiningSeconds
        }.reduce(0, +)
        var pauses: [PauseRow] = []
        var stops = 0
        for (i, tp) in tps.enumerated() where i > 0 {
            if ToolpathStats.stopsBefore(tp, after: tps[i - 1]) { stops += 1 }
            if let p = tps[i - 1].pauseAfter { pauses.append(PauseRow(after: tps[i - 1].name, text: p.text(afterToolpath: tps[i - 1].name))) }
        }
        return JobSummary(rows: rows, sequence: sequence(of: tps), pauses: pauses, stops: stops,
                          machiningSeconds: total, toolChangeSeconds: toolChangeSeconds)
    }

    /// Consecutive toolpaths sharing a tool form one load.
    static func sequence(of toolpaths: [Toolpath]) -> [ToolLoad] {
        var out: [(id: UUID, load: ToolLoad)] = []
        for tp in toolpaths {
            if let last = out.last, last.id == tp.tool.id {
                out[out.count - 1].load.toolpathNames.append(tp.name)
            } else {
                out.append((tp.tool.id, ToolLoad(number: tp.tool.number, name: tp.tool.name, toolpathNames: [tp.name])))
            }
        }
        return out.map(\.load)
    }
}
