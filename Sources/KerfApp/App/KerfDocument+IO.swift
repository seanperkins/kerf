import AppKit
import CADCore
import CAMCore
import Foundation
import PostCore
import UniformTypeIdentifiers

/// File-menu actions added by the io workstream (job sheet, extra formats, templates, print).
extension KerfDocument {
    /// Job sheet for the current state: calculated toolpaths in the shared export order.
    func makeJobSheet(notes: String = "") -> JobSheet {
        let group = UserDefaults.standard.bool(forKey: GCodeExporter.groupByToolKey)
        return JobSheet.make(project: project, results: results, library: toolLibrary.library, profile: postProfile,
                             groupByTool: group, jobName: document.name, notes: notes)
    }

    /// Enabled, calculated toolpaths (for previews and the job sheet picture).
    var calculatedToolpaths: [Toolpath] {
        let group = UserDefaults.standard.bool(forKey: GCodeExporter.groupByToolKey)
        return GCodeExporter.toolpaths(scope: .all, operations: project.operations, results: results, groupByTool: group)
    }

    func jobSheetHTML(notes: String = "") -> String {
        let png = DesignSnapshot.png(document: document, toolpaths: calculatedToolpaths,
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
