import AppKit
import CADCore
import CAMCore
import Foundation
import UniformTypeIdentifiers

/// Applies saved toolpath templates to a project.
enum TemplateService {
    struct Outcome: Equatable {
        var added: Int
        /// Names of toolpaths whose selector matched no vectors.
        var unmatched: [String]
        /// 3D toolpaths left out because the design has no model.
        var skipped: Int
    }

    /// Adds the template's toolpaths (converted to the document's units, unique names) and any
    /// tools the project does not know yet.
    @discardableResult
    static func apply(_ template: ToolpathTemplate, to project: inout KerfProject, library: ToolLibrary) -> Outcome {
        let f = template.units.factor(to: project.document.units)
        let resolved = template.resolve(in: project.document)
        var names = Set(project.operations.map(\.setup.name))
        var outcome = Outcome(added: 0, unmatched: [], skipped: template.entries.count - resolved.count)
        for (op, matched) in resolved {
            var o = f == 1 ? op : op.scaled(by: f)
            var setup = o.setup
            var name = setup.name
            var n = 2
            while names.contains(name) { name = "\(setup.name) \(n)"; n += 1 }
            setup.name = name
            names.insert(name)
            o = o.with(setup: setup)
            project.upsertOperation(o)
            outcome.added += 1
            if matched == 0 { outcome.unmatched.append(name) }
        }
        let known = project.mergedTools(with: library)
        for t in template.tools where known.tool(id: t.id) == nil { project.tools.append(t) }
        return outcome
    }

    static func summary(_ o: Outcome) -> String {
        var lines = ["Added \(o.added) toolpath\(o.added == 1 ? "" : "s")."]
        if !o.unmatched.isEmpty {
            lines.append("No matching vectors for: \(o.unmatched.joined(separator: ", ")). Select vectors and use \"Use Current Selection\".")
        }
        if o.skipped > 0 { lines.append("\(o.skipped) 3D toolpath(s) skipped: the design has no 3D model.") }
        lines.append("Press Calculate All to generate them.")
        return lines.joined(separator: "\n")
    }
}

extension KerfDocument {
    /// Toolpaths → Save Toolpath Template…
    func runSaveTemplatePanel() {
        let template = ToolpathTemplate.make(from: project, library: toolLibrary.library)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ToolpathTemplate.fileExtension) ?? .json]
        panel.nameFieldStringValue = document.name + " toolpaths." + ToolpathTemplate.fileExtension
        panel.message = "Save these toolpaths as a template. Each one remembers the layer and kind of its vectors."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try template.encoded().write(to: url, options: .atomic)
        } catch {
            alert = AlertMessage(title: "Could not save the template", message: error.localizedDescription)
        }
    }

    /// Toolpaths → Apply Toolpath Template…
    func runApplyTemplatePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ToolpathTemplate.fileExtension) ?? .json]
        panel.message = "Apply a toolpath template. Vectors are picked by layer name and open/closed kind."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let template = try ToolpathTemplate.decode(from: Data(contentsOf: url))
            var outcome = TemplateService.Outcome(added: 0, unmatched: [], skipped: 0)
            let lib = toolLibrary.library
            perform("Apply Toolpath Template") { outcome = TemplateService.apply(template, to: &$0, library: lib) }
            alert = AlertMessage(title: "Toolpath template applied", message: TemplateService.summary(outcome))
        } catch {
            alert = AlertMessage(title: "Could not open the template", message: error.localizedDescription)
        }
    }
}
