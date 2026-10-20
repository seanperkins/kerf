import CADCore
import CAMCore
import Foundation

/// Sheets opened by the drawing tools (one `DocumentSheet.drawing` case keeps the shared enum
/// change small).
enum DrawingSheet: String, Identifiable {
    case dogbone
    var id: String { rawValue }
}

/// Drawing-area commands on the selection. Each mutates `project` in place and returns the new
/// selection (or nil when nothing changed).
enum VectorCommands {
    /// Geometry tolerance for the document's units.
    static func tolerance(_ units: LengthUnit) -> Double { units == .inch ? 0.0005 : 0.01 }

    /// Replaces a shape's paths in place: parametric/text provenance is dropped.
    static func replacePaths(_ id: UUID, with paths: [Path], operation: String, in project: inout KerfProject) {
        guard let i = project.document.shapes.firstIndex(where: { $0.id == id }) else { return }
        var s = project.document.shapes[i]
        guard s.paths != paths else { return }
        s.paths = paths
        s.origin = .derived(operation: operation)
        project.document.shapes[i] = s
    }

    /// Editable (unlocked, on an editable layer) shapes among `ids`, in order.
    static func editableShapes(_ ids: [UUID], in project: KerfProject) -> [Shape] {
        project.document.shapes(ids: ids).filter(project.isEditable)
    }

    // MARK: Dog-bones

    /// Adds corner relief to the closed paths of the selection. Returns the number of corners.
    @discardableResult
    static func dogbone(_ ids: [UUID], toolDiameter: Double, style: Dogbone.Style, side: Dogbone.CutSide,
                        maxAngle: Double, in project: inout KerfProject) -> Int {
        guard toolDiameter > 0 else { return 0 }
        var count = 0
        for s in editableShapes(ids, in: project) where s.paths.contains(where: \.isClosed) {
            let n = Dogbone.reliefCount(s.paths, radius: toolDiameter / 2, style: style, side: side, maxAngle: maxAngle)
            guard n > 0 else { continue }
            count += n
            let paths = Dogbone.apply(to: s.paths, radius: toolDiameter / 2, style: style, side: side, maxAngle: maxAngle)
            replacePaths(s.id, with: paths, operation: "dog-bone", in: &project)
        }
        return count
    }
}
