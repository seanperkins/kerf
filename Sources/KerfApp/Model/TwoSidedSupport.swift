import CADCore
import CAMCore
import Foundation

/// Double-sided jobs: which side operations belong to and the per-side output project.
extension KerfProject {
    static let bottomLayerName = "Bottom Side"

    /// Side an operation machines (from its vectors' layers). nil = vectors on both sides.
    /// Operations without vectors (3D relief) are on the top side.
    func side(of op: AnyOperation) -> JobSide? {
        guard document.job.isTwoSided else { return .top }
        return document.side(ofShapes: op.setup.shapeIDs)
    }

    /// What is exported for one side: that side's operations and its Z zero.
    func sideProject(_ side: JobSide) -> KerfProject {
        guard document.job.isTwoSided else { return self }
        var p = self
        p.document.job = document.job.forSide(side)
        p.operations = operations.filter { self.side(of: $0) == side }
        return p
    }

    /// Makes sure a two-sided job has a layer for the bottom side.
    mutating func ensureBottomLayer() {
        guard document.job.isTwoSided, !document.layers.contains(where: { $0.side == .bottom }) else { return }
        let id = addLayer(named: Self.bottomLayerName)
        if let i = document.layers.firstIndex(where: { $0.id == id }) { document.layers[i].side = .bottom }
    }
}

extension KerfDocument {
    /// The project export, validation, previews and the job sheet use: the side being shown
    /// when the job is two-sided, otherwise the whole project.
    var outputProject: KerfProject { project.sideProject(activeSide) }

    var isTwoSided: Bool { document.job.isTwoSided }

    /// Project for one export: a single toolpath uses its own side, "all" the shown side.
    func outputProject(for scope: GCodeExportScope) -> KerfProject {
        if case .operation(let id) = scope, let op = operation(id), let side = project.side(of: op) {
            return project.sideProject(side)
        }
        return outputProject
    }

    func isOnActiveSide(_ shape: Shape) -> Bool { !isTwoSided || document.side(of: shape) == activeSide }

    func isOnActiveSide(_ op: AnyOperation) -> Bool { !isTwoSided || project.side(of: op) == activeSide }

    /// Shows the other side (selection is cleared: shapes on the hidden side cannot be edited).
    func showSide(_ side: JobSide) {
        guard isTwoSided, side != activeSide else { return }
        clearSelection()
        activeSide = side
    }

    /// Moves a layer to a side (one undo step).
    func setLayerSide(_ layerID: UUID, _ side: JobSide) {
        perform("Move Layer to \(side == .top ? "Top" : "Bottom") Side") { p in
            if let i = p.document.layers.firstIndex(where: { $0.id == layerID }) {
                p.document.layers[i].side = side == .top ? nil : .bottom
            }
        }
    }
}

extension JobSide {
    var displayName: String { self == .top ? "Top" : "Bottom" }
}

extension FlipAxis {
    var displayName: String { self == .leftRight ? "Left–right (about Y)" : "Top–bottom (about X)" }
}
