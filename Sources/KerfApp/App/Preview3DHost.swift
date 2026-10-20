import CADCore
import CAMCore
import SwiftUI

/// Hosts the 3D material-removal simulation (Sources/KerfApp/Preview/) for the document's
/// calculated toolpaths (all, visible or selected; see `PreviewScope`). The 2D overlay is drawn
/// by the design canvas itself.
struct Preview3DHost: View {
    @ObservedObject var document: KerfDocument
    @AppStorage(GCodeExporter.groupByToolKey) private var groupByTool = false
    @AppStorage(PreviewScope.storageKey) private var scope = PreviewScope.all
    @ObservedObject private var timeStore = TimeEstimateStore.shared
    @AppStorage(SimulationPreviewModel.showVectorsKey) private var showVectors = false

    /// Visible design vectors on the shown side / sheet, flattened (only when drawn in 3D).
    var vectors: [[Vec2]] {
        guard showVectors else { return [] }
        let project = document.outputProject
        return project.document.shapes.filter { project.isVisible($0) && document.isOnActiveSide($0) }
            .flatMap(\.paths).compactMap { path in
                var pts = path.flattened(tolerance: 0.005)
                if path.isClosed, let first = pts.first { pts.append(first) }
                return pts.count >= 2 ? pts : nil
            }
    }

    /// Calculated toolpaths of the chosen scope, in machining order.
    var toolpaths: [Toolpath] {
        scope.toolpaths(operations: document.outputProject.operations, results: document.results,
                        hidden: document.hiddenToolpaths, selected: document.selectedOperationID,
                        groupByTool: groupByTool)
    }

    var body: some View {
        SimulationPreviewView(
            job: document.outputProject.document.job, units: document.document.units, toolpaths: toolpaths,
            rapidRate: SimulationPreviewView.rapidRate(for: document.postProfile, units: document.document.units),
            scope: $scope, emptyMessage: scope.emptyMessage, documentName: document.document.name,
            vectors: vectors)
        .onChange(of: timeStore.settings) { _, _ in document.refreshTimeEstimates() }
    }
}
