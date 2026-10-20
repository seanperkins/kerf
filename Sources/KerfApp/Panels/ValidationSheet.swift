import CADCore
import CAMCore
import PostCore
import SwiftUI

/// Toolpaths > Check Toolpaths…: validator warnings and errors for every toolpath and for the
/// combined program, with a shortcut to select the offending toolpath.
struct ValidationSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @State private var report: ValidationReport?
    @State private var groupByTool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Check Toolpaths").font(.title2.bold())
                Spacer()
                Text(document.postProfile.name).foregroundStyle(.secondary)
            }
            if let r = report {
                summary(r)
                List {
                    ForEach(r.sections) { section in
                        Section {
                            if section.issues.isEmpty {
                                Label("No problems found", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                            }
                            ForEach(Array(section.issues.enumerated()), id: \.offset) { _, issue in
                                IssueRow(issue: issue)
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                Spacer()
                                if let id = section.operationID {
                                    Button("Show") {
                                        document.sidebarTab = .toolpaths
                                        document.selectedOperationID = id
                                        dismiss()
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Toggle("Combined program grouped by tool", isOn: $groupByTool)
                Spacer()
                Button("Recheck") { run() }
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .onAppear { run() }
        .onChange(of: groupByTool) { _, _ in run() }
    }

    private func summary(_ r: ValidationReport) -> some View {
        Group {
            if r.isClean {
                Label("All toolpaths passed the validator.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Label("\(r.errorCount) error(s) and \(r.warningCount) warning(s). Errors must be fixed before cutting; warnings are worth a look.",
                      systemImage: r.errorCount > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(r.errorCount > 0 ? .red : .orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func run() {
        let stale = document.project.operations.filter { $0.setup.isEnabled && document.isStale($0.id) }.map(\.id)
        if !stale.isEmpty { document.calculateNow(stale) }
        report = ValidationReport.make(project: document.project, results: document.results,
                                       profile: document.postProfile, groupByTool: groupByTool)
    }
}

struct IssueRow: View {
    var issue: GCodeIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? .red : .orange)
            Text(issue.message).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let l = issue.line { Text("line \(l)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}
