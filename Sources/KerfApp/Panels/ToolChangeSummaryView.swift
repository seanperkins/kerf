import CADCore
import CAMCore
import SwiftUI

/// Bottom of the Toolpaths sidebar: total time and the tool-change sequence of the combined
/// program (grouped by tool, as "Save All Toolpaths" does by default).
struct ToolChangeSummaryView: View {
    @ObservedObject var document: KerfDocument
    /// The live settings, so a changed tool-change allowance redraws the total at once.
    @ObservedObject private var timeStore = TimeEstimateStore.shared
    @AppStorage(GCodeExporter.groupByToolKey) private var groupByTool = false
    @State private var expanded = false
    @State private var memo = SummaryMemo()

    var body: some View {
        let s = memo.summary(operations: document.outputProject.operations, results: document.results, groupByTool: groupByTool,
                             settings: timeStore.settings, rapidRate: document.rapidRateInDocumentUnits, units: document.units,
                             motion: document.motionSeconds)
        VStack(alignment: .leading, spacing: 4) {
            if s.hasEstimate {
                // Longest wording that fits the sidebar; "4 tools · 3 changes" shortens before the time does.
                let time = "Estimated time: " + ToolpathCalculator.formatDuration(s.totalSeconds)
                let tools = s.sequence.count
                let toolsText = tools == 0 ? "No tools" : "\(tools) tool\(tools == 1 ? "" : "s")"
                let pauses = s.pauses.count
                let pauseText = pauses == 0 ? "" : " · \(pauses) pause\(pauses == 1 ? "" : "s")"
                ViewThatFits(in: .horizontal) {
                    header(time, tools == 0 ? toolsText : "\(toolsText) · \(s.toolChanges) change\(s.toolChanges == 1 ? "" : "s")" + pauseText)
                    header(time, tools == 0 ? toolsText : "\(toolsText) · \(s.toolChanges) change\(s.toolChanges == 1 ? "" : "s")")
                    header(time, toolsText)
                    header(time, nil)
                }
                .help(totalHelp(s))
            } else {
                header("Not calculated yet", nil)
                    .help("Calculate the toolpaths to see the estimated time")
            }
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Group by tool", isOn: $groupByTool).font(.caption).toggleStyle(.checkbox)
                    ForEach(Array(s.sequence.enumerated()), id: \.offset) { i, load in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(i == 0 ? "Load" : "Change to") T\(load.number) · \(load.name)").font(.caption)
                            Text(load.toolpathNames.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    ForEach(Array(s.pauses.enumerated()), id: \.offset) { _, p in
                        Label("Pause after \(p.after): \(p.text)", systemImage: "pause.circle")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    let missing = s.rows.filter { $0.isEnabled && $0.estimatedSeconds == nil }.count
                    if missing > 0 {
                        Text("\(missing) enabled toolpath\(missing == 1 ? " is" : "s are") not calculated.")
                            .font(.caption2).foregroundStyle(Color.warningText)
                    }
                }
                .padding(.top, 2)
            } label: {
                Text("Tool changes").font(.caption)
            }
        }
    }

    /// The last summary and what it was made from. Timing the program is a motion solve over
    /// every move, and this view is always on screen and redraws with every document change, so
    /// the summary is rebuilt only when its inputs change: the operations, the results (their
    /// toolpaths are new objects after each calculation, their estimates after a settings change),
    /// the grouping, the settings, and the machine's rapid rate.
    final class SummaryMemo {
        private var key: Int?
        private var summary: JobSummary?

        func summary(operations: [AnyOperation], results: [UUID: ToolpathResult], groupByTool: Bool,
                     settings: TimeEstimateSettings, rapidRate: Double, units: LengthUnit,
                     motion: ([Toolpath]) -> TimeInterval) -> JobSummary {
            var h = Hasher()
            h.combine(operations)
            for (id, r) in results.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                h.combine(id); h.combine(r.toolpaths.map(\.id)); h.combine(r.toolpaths.map(\.pauseAfter))
                h.combine(r.estimatedSeconds); h.combine(r.error)
            }
            h.combine(groupByTool); h.combine(settings); h.combine(rapidRate); h.combine(units)
            let k = h.finalize()
            if let summary, key == k { return summary }
            let s = JobSummary.make(operations: operations, results: results, groupByTool: groupByTool,
                                    toolChangeSeconds: settings.toolChangeSeconds, motion: motion)
            key = k; summary = s
            return s
        }
    }

    private func header(_ time: String, _ detail: String?) -> some View {
        HStack {
            Text(time).font(.caption.bold())
            Spacer(minLength: 8)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .lineLimit(1)
    }

    /// What the total is made of, so it can be compared with the 3D preview's.
    private func totalHelp(_ s: JobSummary) -> String {
        var text = "Cutting and rapids: " + ToolpathCalculator.formatDuration(s.machiningSeconds)
        if s.stops > 0 {
            let what = s.pauses.isEmpty ? "tool change\(s.stops == 1 ? "" : "s")"
                : "stop\(s.stops == 1 ? "" : "s") (tool changes and pauses)"
            text += " + \(s.stops) \(what) at " + ToolpathCalculator.formatDuration(s.toolChangeSeconds) + " each"
        }
        return text + ". Set the tool-change allowance in the 3D preview's time settings."
    }
}
