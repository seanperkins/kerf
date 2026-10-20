import AppKit
import CADCore
import CAMCore
import PostCore
import SwiftUI
import UniformTypeIdentifiers

/// Save All Toolpaths: one combined program (grouped by tool or in list order), one file per
/// toolpath, or one file per tool. Shows each file's tools, time and validator result.
struct SaveAllToolpathsSheet: View {
    @ObservedObject var document: KerfDocument
    @ObservedObject var catalog = PostProfileCatalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mode: SaveAllMode = .oneFileGroupedByTool
    @State private var profileID = ""
    @State private var posted: [(file: PlannedGCodeFile, result: GCodeExportResult)] = []
    @State private var confirmErrors = false

    private var profile: PostProfile { catalog.profile(id: profileID) }
    private var hasErrors: Bool { posted.contains { $0.result.hasErrors || $0.result.text == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save All Toolpaths").font(.title2.bold())
            Form {
                Picker("Output", selection: $mode) {
                    ForEach(SaveAllMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Picker("Machine / post", selection: $profileID) {
                    ForEach(catalog.profiles) { Text($0.name).tag($0.id) }
                }
            }
            .formStyle(.grouped)
            .frame(height: 190)
            if posted.isEmpty {
                Label("There are no calculated, enabled toolpaths to save.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                List(Array(posted.enumerated()), id: \.offset) { _, item in fileRow(item.file, item.result) }
            }
            HStack {
                Button("Check Toolpaths…") { document.sheet = .validation }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(mode.isSingleFile ? "Save…" : "Choose Folder…") {
                    if hasErrors { confirmErrors = true } else { save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(posted.allSatisfy { $0.result.text == nil })
            }
        }
        .padding(20)
        .frame(width: 620, height: 600)
        .onAppear {
            profileID = document.postProfile.id
            run()
        }
        .onChange(of: mode) { _, _ in run() }
        .onChange(of: profileID) { _, _ in run() }
        .alert("The validator reported errors", isPresented: $confirmErrors) {
            Button("Save Anyway", role: .destructive) { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some programs have errors or could not be generated. Running them may damage the machine or the work.")
        }
    }

    private func fileRow(_ file: PlannedGCodeFile, _ r: GCodeExportResult) -> some View {
        let loads = JobSummary.sequence(of: file.toolpaths)
        let secs = MachiningTimeEstimator.estimate(file.toolpaths, rapidRate: document.rapidRateInDocumentUnits)
        let errors = r.issues.filter { $0.severity == .error }.count
        let warnings = r.issues.count - errors
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "doc.text")
                Text(file.fileName).font(.body.monospaced())
                Spacer()
                Text(ToolpathCalculator.formatDuration(secs)).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(loads.map { "T\($0.number) \($0.name)" }.joined(separator: " → "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let e = r.errorMessage {
                Label(e, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
            } else if errors + warnings > 0 {
                Label("\(errors) error(s), \(warnings) warning(s)", systemImage: errors > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(errors > 0 ? .red : .orange)
            } else {
                Label("No problems found", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private func run() {
        let stale = document.project.operations.filter { $0.setup.isEnabled && document.isStale($0.id) }.map(\.id)
        if !stale.isEmpty { document.calculateNow(stale) }
        let files = GCodeBatchExport.plan(mode: mode, operations: document.project.operations,
                                          results: document.results, jobName: document.document.name, profile: profile)
        posted = GCodeBatchExport.post(files, project: document.project, profile: profile, jobName: document.document.name)
    }

    private func save() {
        do {
            if mode.isSingleFile {
                guard let item = posted.first, let text = item.result.text else { return }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = item.file.fileName
                if let t = UTType(filenameExtension: profile.fileExtension) { panel.allowedContentTypes = [t] }
                panel.allowsOtherFileTypes = true
                panel.canCreateDirectories = true
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try text.write(to: url, atomically: true, encoding: .utf8)
            } else {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.prompt = "Save Here"
                panel.message = "Choose a folder for \(posted.count) G-code files"
                guard panel.runModal() == .OK, let dir = panel.url else { return }
                try GCodeBatchExport.write(posted, to: dir)
            }
            if document.project.postProfileID != profileID { document.setPostProfile(profileID) }
            dismiss()
        } catch {
            document.alert = AlertMessage(title: "Could not save G-code", message: error.localizedDescription)
        }
    }
}
