import AppKit
import CADCore
import CAMCore
import Foundation
import PostCore
import SwiftUI
import UniformTypeIdentifiers

/// File-menu actions added by the io workstream (job sheet, extra formats, templates, print).
extension KerfDocument {
    /// Job sheet for the current state: calculated toolpaths in the shared export order.
    func makeJobSheet(notes: String = "") -> JobSheet {
        let group = UserDefaults.standard.bool(forKey: GCodeExporter.groupByToolKey)
        return JobSheet.make(project: outputProject, results: results, library: toolLibrary.library, profile: postProfile,
                             groupByTool: group,
                             jobName: document.name + (isTwoSided ? " (\(activeSide.displayName) side)" : ""), notes: notes)
    }

    /// Enabled, calculated toolpaths (for previews and the job sheet picture).
    var calculatedToolpaths: [Toolpath] {
        let group = UserDefaults.standard.bool(forKey: GCodeExporter.groupByToolKey)
        return GCodeExporter.toolpaths(scope: .all, operations: outputProject.operations, results: results, groupByTool: group)
    }

    func jobSheetHTML(notes: String = "") -> String {
        let png = DesignSnapshot.png(document: outputProject.document, toolpaths: calculatedToolpaths,
                                     size: CGSize(width: 900, height: 600))
        return makeJobSheet(notes: notes).html(previewPNG: png)
    }

    /// File > Job Sheet…: saves an HTML sheet and opens it (print from the browser).
    func runJobSheetPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = document.name + " Job Sheet.html"
        panel.message = "Save a printable job sheet (opens in your browser)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(jobSheetHTML().utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            alert = AlertMessage(title: "Job sheet failed", message: error.localizedDescription)
        }
    }
}

// MARK: Job templates

extension KerfDocument {
    /// File > Save as Template…: stores this project (job, layers, vectors, toolpaths, post).
    func runSaveTemplatePanel(store: JobTemplateStore = JobTemplateStore()) {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let panel = NSSavePanel()
        panel.directoryURL = store.directory
        panel.allowedContentTypes = [.kerfProject]
        panel.nameFieldStringValue = document.name
        panel.message = "Save this job (material, layers, vectors and toolpaths) as a template"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var p = project
            p.refreshToolSnapshot(from: toolLibrary.library)
            if url.deletingLastPathComponent().standardizedFileURL == store.directory.standardizedFileURL {
                try store.save(p, name: url.deletingPathExtension().lastPathComponent)
            } else {
                try p.encoded().write(to: url, options: .atomic)
            }
        } catch {
            alert = AlertMessage(title: "Template not saved", message: error.localizedDescription)
        }
    }
}

/// File > New from Template submenu and Save as Template.
struct TemplateMenu: View {
    var document: KerfDocument?
    var open: (KerfProject) -> Void
    private let store = JobTemplateStore()

    var body: some View {
        Menu("New from Template") {
            let entries = store.templates()
            if entries.isEmpty { Text("No templates yet (File > Save as Template…)") }
            ForEach(entries) { entry in
                Button(entry.name) {
                    do { open(try store.instantiate(entry)) } catch {
                        let a = NSAlert()
                        a.messageText = "The template could not be opened"
                        a.informativeText = ImportService.describe(error)
                        a.runModal()
                    }
                }
            }
            Divider()
            Button("Open Templates Folder") {
                try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(store.directory)
            }
        }
        Button("Save as Template…") { document?.runSaveTemplatePanel() }
            .disabled(document == nil)
    }
}
