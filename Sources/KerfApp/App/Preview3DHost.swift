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

    /// Calculated toolpaths of the chosen scope, in machining order.
    var toolpaths: [Toolpath] {
        scope.toolpaths(operations: document.project.operations, results: document.results,
                        hidden: document.hiddenToolpaths, selected: document.selectedOperationID,
                        groupByTool: groupByTool)
    }

    var body: some View {
        SimulationPreviewView(
            job: document.document.job, units: document.document.units, toolpaths: toolpaths,
            rapidRate: SimulationPreviewView.rapidRate(for: document.postProfile, units: document.document.units),
            scope: $scope, emptyMessage: scope.emptyMessage, documentName: document.document.name)
        .onChange(of: timeStore.settings) { _, _ in document.refreshTimeEstimates() }
    }
}
