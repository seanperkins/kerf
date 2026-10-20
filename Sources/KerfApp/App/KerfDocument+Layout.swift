import AppKit
import CADCore
import CAMCore
import Foundation
import UniformTypeIdentifiers

/// Layout commands (job sheet, sheets) kept out of KerfDocument.swift.
extension KerfDocument {
    /// File > Export Job Sheet…: recalculates stale toolpaths, writes a printable HTML setup
    /// sheet and opens it in the default browser.
    @MainActor
    func exportJobSheet() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (document.name.isEmpty ? "Untitled" : document.name) + " job sheet.html"
        panel.message = "Save a printable operator sheet (origin, tools and toolpath order)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            let stale = project.operations.filter { $0.setup.isEnabled && isStale($0.id) }.map(\.id)
            if !stale.isEmpty { _ = await calculateAndWait(stale) }
            let html = JobSheetHTML.render(makeJobSheet())
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            } catch {
                alert = AlertMessage(title: "Job sheet not saved", message: error.localizedDescription)
            }
        }
    }

    func makeJobSheet(date: Date = Date()) -> JobSheet {
        JobSheet.make(project: project, results: results, profile: postProfile,
                      groupByTool: UserDefaults.standard.bool(forKey: GCodeExporter.groupByToolKey),
                      rapidRate: rapidRateInDocumentUnits, date: date, sheets: JobSheet.sheets(of: project))
    }

    /// Design > Layout > Sheet on Material: swaps which nesting sheet is machined.
    func showSheetOnMaterial(_ n: Int) {
        perform("Sheet \(n) on Material") { NestSheets.activate(n, in: &$0.document) }
        requestCanvas(.fit)
    }
}
