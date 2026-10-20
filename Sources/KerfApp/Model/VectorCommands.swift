import CADCore
import CAMCore
import Foundation

/// Sheets opened by the drawing tools (one `DocumentSheet.drawing` case keeps the shared enum
/// change small).
enum DrawingSheet: String, Identifiable {
    case dogbone, arrayLinear, validator
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
        s.text = nil
        project.document.shapes[i] = s
    }

    // MARK: Text

    /// Re-outlines a live text shape from `spec` (same transform → same anchor).
    static func updateText(_ id: UUID, spec: TextSpec, in project: inout KerfProject) throws {
        guard let i = project.document.shapes.firstIndex(where: { $0.id == id }),
              project.isEditable(project.document.shapes[i]) else { return }
        let rebuilt = try TextOutliner().shape(for: spec, layerID: project.document.shapes[i].layerID)
        var s = project.document.shapes[i]
        s.paths = rebuilt.paths
        s.origin = rebuilt.origin
        s.text = spec
        if s.name.isEmpty || s.name == project.document.shapes[i].text?.string.replacingOccurrences(of: "\n", with: " ") {
            s.name = rebuilt.name
        }
        project.document.shapes[i] = s
    }

    /// Turns live text into plain vectors (no further text editing).
    static func convertTextToCurves(_ ids: Set<UUID>, in project: inout KerfProject) {
        for i in project.document.shapes.indices where ids.contains(project.document.shapes[i].id) {
            guard project.document.shapes[i].text != nil else { continue }
            project.document.shapes[i].text = nil
            project.document.shapes[i].origin = .derived(operation: "text to curves")
        }
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

    // MARK: Validator

    /// Shapes the validator looks at: the selection, or every visible shape when nothing is selected.
    static func validationScope(_ ids: [UUID], in project: KerfProject) -> [Shape] {
        ids.isEmpty ? project.document.shapes.filter(project.isVisible) : project.document.shapes(ids: ids)
    }

    /// Applies the validator's automatic repairs. Returns the number of issues repaired.
    @discardableResult
    static func repair(_ issues: [VectorIssue], in project: inout KerfProject) -> Int {
        let fixable = issues.filter(\.kind.isFixable)
        let ids = Set(fixable.map(\.shapeID))
        let shapes = project.document.shapes.filter { ids.contains($0.id) && project.isEditable($0) }
        let editable = Set(shapes.map(\.id))
        let used = fixable.filter { editable.contains($0.shapeID) }
        let tol = tolerance(project.document.units)
        let fixed = VectorValidator.fix(shapes, issues: used, tolerance: tol)
        let kept = Set(fixed.map(\.id))
        project.deleteShapes(editable.subtracting(kept))
        for s in fixed { project.document.replace(s) }
        return used.count
    }

    // MARK: Arrays

    /// Adds one copy of the selection per transform (fresh IDs, each copy's groups remapped).
    /// Returns the new shape IDs.
    static func arrayCopies(_ ids: [UUID], transforms: [Transform2D], in project: inout KerfProject) -> [UUID] {
        let shapes = project.document.expandToGroups(ids).compactMap { project.document.shape(id: $0) }
        guard !shapes.isEmpty else { return [] }
        let layers = Set(project.document.layers.map(\.id))
        var newIDs: [UUID] = []
        for t in transforms {
            for var c in ShapeClipboard.copies(of: shapes, offset: .zero, layers: layers, fallbackLayer: shapes[0].layerID) {
                c = c.transformed(t)
                if !t.isConformal { c.origin = .derived(operation: "transform") }
                project.document.add(c)
                newIDs.append(c.id)
            }
        }
        return newIDs
    }

    /// Rectangular array: rows × columns including the original.
    static func rectangularArray(_ ids: [UUID], rows: Int, columns: Int, x: Double, y: Double,
                                 spacing: ArrayLayout.Spacing, in project: inout KerfProject) -> [UUID] {
        let size = project.bounds(of: Set(project.document.expandToGroups(ids))).size
        let offsets = ArrayLayout.rectangular(rows: rows, columns: columns, x: x, y: y, spacing: spacing, size: size)
        return arrayCopies(ids, transforms: offsets.map { .translation($0) }, in: &project)
    }
}
