import CADCore
import CAMCore
import Foundation

/// Undoable drawing actions on the focused document (node-edit extras etc.).
extension KerfDocument {
    /// Finds vectors lying on top of others (selection, or the whole design) and deletes the
    /// extra copies, then reports how many went.
    func deleteDuplicateVectors() {
        let scope = VectorCommands.validationScope(selectedShapes.map(\.id), in: project)
        let dups = VectorValidator.duplicates(scope, tolerance: VectorCommands.tolerance(units))
        var removed = 0
        if !dups.isEmpty { perform("Delete Duplicates") { removed = VectorCommands.repair(dups, in: &$0) } }
        alert = AlertMessage(title: "Duplicate Vectors",
                             message: removed == 0 ? "No duplicate or overlapping vectors found."
                                 : "Deleted \(removed) duplicate or overlapping vector\(removed == 1 ? "" : "s").")
    }

    /// Makes the single selected node the start of its closed vector.
    func setStartAtSelectedNode() {
        guard nodeSelection.count == 1, let r = nodeSelection.first else { return }
        var ok = false
        perform("Set Start Point") { ok = $0.editNodes(of: r.shapeID) { ShapeNodes.settingStart($0, r) } }
        if ok { nodeSelection = [NodeRef(shapeID: r.shapeID, path: r.path, node: 0)] }
    }
}
