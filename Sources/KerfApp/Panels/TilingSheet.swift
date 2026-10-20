import AppKit
import CADCore
import CAMCore
import PostCore
import SwiftUI

/// Toolpaths > Save Tiled G-code…: splits a job larger than the machine into tiles, one
/// program each, zeroed at the tile's lower-left corner on the material.
struct TilingSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GCodeExporter.groupByToolKey) private var groupByTool = false
    @State private var settings = TilingSettings(tileWidth: 60, tileHeight: 96)
    @State private var files: [TiledExport.File] = []
    @State private var calcTask: Task<Void, Never>?
    @State private var calculatingCount = 0
    @State private var confirmErrors = false

    private var hasErrors: Bool { files.contains { $0.result.hasErrors || $0.result.text == nil } }

    var body: some View {
        let u = document.units
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Tiled G-code").font(.title2.bold())
            Text("Each tile is cut with the material moved so the tile is under the machine. Zero X and Y at the "
                 + "tile's corner on the material (given in each file's header). Cuts that cross a seam stop at it "
                 + "and continue in the next tile; overlap re-cuts a band on both sides of each seam.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                LengthField("Largest tile width (X)", value: $settings.tileWidth, units: u)
                LengthField("Largest tile height (Y)", value: $settings.tileHeight, units: u)
                LengthField("Overlap at seams", value: $settings.overlap, units: u)
            }
            if calcTask != nil {
                CalculationProgressView(count: calculatingCount) { calcTask?.cancel(); calcTask = nil }
            } else if files.isEmpty {
                Label("There are no calculated, enabled toolpaths to save.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                List(Array(files.enumerated()), id: \.offset) { _, f in row(f) }
            }
            HStack {
                Text("\(files.count) file\(files.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Choose Folder…") { if hasErrors { confirmErrors = true } else { save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(files.allSatisfy { $0.result.text == nil })
            }
        }
        .padding(20)
        .frame(width: 600, height: 560)
        .onAppear {
            settings = TiledExport.defaultSettings(profile: document.postProfile, units: document.units)
            run()
        }
        .onDisappear { calcTask?.cancel() }
        .onChange(of: settings) { _, _ in if calcTask == nil { post() } }
        .alert("The validator reported errors", isPresented: $confirmErrors) {
            Button("Save Anyway", role: .destructive) { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some tiles have errors or could not be generated. Running them may damage the machine or the work.")
        }
    }

    private func row(_ f: TiledExport.File) -> some View {
        let errors = f.result.issues.filter { $0.severity == .error }.count
        let warnings = f.result.issues.count - errors
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: "square.split.2x2")
                Text(f.fileName).font(.body.monospaced())
                Spacer()
                Text("\(f.tile.toolpaths.count) toolpath\(f.tile.toolpaths.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            Text("Zero XY at material X \(RulerTicks.label(f.tile.region.min.x)) Y \(RulerTicks.label(f.tile.region.min.y)); "
                 + "tile \(RulerTicks.label(f.tile.region.width)) x \(RulerTicks.label(f.tile.region.height)) \(document.units.abbreviation)")
                .font(.caption).foregroundStyle(.secondary)
            if let e = f.result.errorMessage {
                Label(e, systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
            } else if errors + warnings > 0 {
                Label("\(errors) error(s), \(warnings) warning(s)", systemImage: errors > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(errors > 0 ? .red : .orange)
                    .help(f.result.issues.map(\.message).joined(separator: "\n"))
            } else {
                Label("No problems found", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green)
            }
        }
    }

    private func run() {
        calcTask?.cancel()
        calcTask = nil
        let stale = document.project.operations.filter { $0.setup.isEnabled && document.isStale($0.id) }.map(\.id)
        guard !stale.isEmpty else { post(); return }
        files = []
        calculatingCount = stale.count
        calcTask = Task { @MainActor in
            let done = await document.calculateAndWait(stale)
            guard done, !Task.isCancelled else { return }
            calcTask = nil
            post()
        }
    }

    private func post() {
        guard settings.tileWidth > 0, settings.tileHeight > 0 else { files = []; return }
        files = TiledExport.files(project: document.project, results: document.results, profile: document.postProfile,
                                  groupByTool: groupByTool, settings: settings)
    }

    private func save() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.message = "Choose a folder for \(files.count) tile programs"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            for f in files {
                guard let text = f.result.text else { continue }
                try text.write(to: dir.appendingPathComponent(f.fileName), atomically: true, encoding: .utf8)
            }
            dismiss()
        } catch {
            document.alert = AlertMessage(title: "Could not save G-code", message: error.localizedDescription)
        }
    }
}
