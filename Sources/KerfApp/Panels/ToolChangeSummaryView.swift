import CADCore
import CAMCore
import SwiftUI

/// Bottom of the Toolpaths sidebar: total time and the tool-change sequence of the combined
/// program (grouped by tool, as "Save All Toolpaths" does by default).
struct ToolChangeSummaryView: View {
    @ObservedObject var document: KerfDocument
    @AppStorage(GCodeExporter.groupByToolKey) private var groupByTool = false
    @State private var expanded = false

    var body: some View {
        let s = JobSummary.make(operations: document.outputProject.operations, results: document.results,
                                groupByTool: groupByTool)
        VStack(alignment: .leading, spacing: 4) {
            // Longest wording that fits the sidebar; "4 tools · 3 changes" shortens before the time does.
            let time = "Estimated time: " + ToolpathCalculator.formatDuration(s.totalSeconds)
            let tools = s.sequence.count
            let toolsText = tools == 0 ? "No tools" : "\(tools) tool\(tools == 1 ? "" : "s")"
            ViewThatFits(in: .horizontal) {
                header(time, tools == 0 ? toolsText : "\(toolsText) · \(s.toolChanges) change\(s.toolChanges == 1 ? "" : "s")")
                header(time, toolsText)
                header(time, nil)
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
                    let missing = s.rows.filter { $0.isEnabled && $0.estimatedSeconds == nil }.count
                    if missing > 0 {
                        Text("\(missing) enabled toolpath\(missing == 1 ? " is" : "s are") not calculated.")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
                .padding(.top, 2)
            } label: {
                Text("Tool changes").font(.caption)
            }
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
}
