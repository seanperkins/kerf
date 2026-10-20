import CADCore
import CAMCore
import Foundation

/// Merging adjacent toolpaths that use the same tool, and splitting them again (toolpaths-2d).
extension KerfProject {
    /// Why the operation cannot be merged with the one after it (nil = it can).
    func mergeWithNextProblem(_ id: UUID) -> String? {
        guard let i = operationIndex(id) else { return "Select a toolpath." }
        guard i + 1 < operations.count else { return "There is no toolpath after this one." }
        let a = operations[i], b = operations[i + 1]
        if a.kind == .relief3D || b.kind == .relief3D { return "3D toolpaths cannot be merged." }
        if a.setup.toolID != b.setup.toolID { return "The next toolpath uses a different tool." }
        return nil
    }

    /// Replaces the operation and the next one with one merged operation (cut in the same order).
    @discardableResult
    mutating func mergeWithNext(_ id: UUID) -> UUID? {
        guard mergeWithNextProblem(id) == nil, let i = operationIndex(id) else { return nil }
        let a = operations[i], b = operations[i + 1]
        let name: String
        if case .merge = a { name = a.setup.name } else { name = "\(a.setup.name) + \(b.setup.name)" }
        guard var merged = MergeOperation.merging([a, b], name: name) else { return nil }
        if case .merge = a { merged.setup.id = a.id }
        merged.setup.isEnabled = a.setup.isEnabled || b.setup.isEnabled
        operations.replaceSubrange(i...(i + 1), with: [.merge(merged)])
        return merged.setup.id
    }

    /// Puts a merged operation's toolpaths back in its place.
    mutating func splitMerged(_ id: UUID) {
        guard let i = operationIndex(id), case .merge(let m) = operations[i] else { return }
        operations.replaceSubrange(i...i, with: m.params.children)
    }
}

extension KerfDocument {
    func mergeOperationWithNext(_ id: UUID) {
        var newID: UUID?
        perform("Merge Toolpaths") { newID = $0.mergeWithNext(id) }
        if let newID { selectedOperationID = newID }
    }

    func splitMergedOperation(_ id: UUID) {
        let first: UUID? = {
            if case .merge(let m) = operation(id) { return m.params.children.first?.id }
            return nil
        }()
        perform("Split Merged Toolpath") { $0.splitMerged(id) }
        if let first { selectedOperationID = first }
    }
}
