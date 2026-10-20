import CADCore
import CAMCore
import Foundation

/// Outcome of calculating one operation. Kept in memory only (recalculated after opening).
struct ToolpathResult: Sendable {
    var toolpaths: [Toolpath]
    var error: String?
    /// The operation exactly as it was when calculated (to detect parameter edits).
    var operation: AnyOperation
    /// `KerfDocument.designRevision` at calculation time (to detect design/tool edits).
    var designRevision: Int
    var estimatedSeconds: TimeInterval

    var isOK: Bool { error == nil && !toolpaths.isEmpty }
}

enum ToolpathCalculator {
    /// Runs the operation's generator. Never throws: failures become `error` text.
    static func calculate(_ op: AnyOperation, project: KerfProject, library: ToolLibrary,
                          designRevision: Int, rapidRate: Double) -> ToolpathResult {
        // Extra nesting sheets parked beside the material are not machined.
        let onMaterial = NestSheets.activeDocument(project.document)
        let context = CAMContext(document: onMaterial, tools: project.mergedTools(with: library))
        if onMaterial.shapes.count != project.document.shapes.count, !op.setup.shapeIDs.isEmpty,
           op.setup.shapeIDs.allSatisfy({ onMaterial.shape(id: $0) == nil && project.document.shape(id: $0) != nil }) {
            return ToolpathResult(toolpaths: [], error: "All of this toolpath's vectors are on a sheet that is not on "
                                      + "the material. Use Design > Layout > Sheet on Material to cut that sheet.",
                                  operation: op, designRevision: designRevision, estimatedSeconds: 0)
        }
        do {
            let tps = try op.generate(in: context)
            let secs = MachiningTimeEstimator.estimate(tps, rapidRate: rapidRate)
            let err = tps.isEmpty ? "No toolpath was generated (check the selected vectors and depths)." : nil
            return ToolpathResult(toolpaths: tps, error: err, operation: op, designRevision: designRevision,
                                  estimatedSeconds: secs)
        } catch {
            return ToolpathResult(toolpaths: [], error: describe(error), operation: op,
                                  designRevision: designRevision, estimatedSeconds: 0)
        }
    }

    /// User-facing message for generator errors.
    static func describe(_ error: Error) -> String {
        switch error {
        case CAMError.notImplemented(let what): return "\(what) is not available in this build yet."
        case CAMError.missingTool: return "The selected tool is not in the tool database."
        case CAMError.missingModel: return "The 3D model for this toolpath is missing."
        case CAMError.noGeometry: return "Select one or more vectors for this toolpath."
        case CAMError.invalidGeometry(let m): return "Invalid geometry: \(m)"
        case CAMError.invalidParameter(let m): return "Invalid parameter: \(m)"
        default: return error.localizedDescription
        }
    }

    /// "1h 02m 05s" / "3m 20s" / "45s".
    static func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, sec) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }
}
