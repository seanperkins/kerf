import CADCore
import CAMCore
import Foundation

/// Undoable drawing actions on the focused document (node-edit extras etc.).
extension KerfDocument {
    /// Makes the single selected node the start of its closed vector.
    func setStartAtSelectedNode() {
        guard nodeSelection.count == 1, let r = nodeSelection.first else { return }
        var ok = false
        perform("Set Start Point") { ok = $0.editNodes(of: r.shapeID) { ShapeNodes.settingStart($0, r) } }
        if ok { nodeSelection = [NodeRef(shapeID: r.shapeID, path: r.path, node: 0)] }
    }
}
