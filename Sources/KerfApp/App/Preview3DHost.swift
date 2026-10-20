import CADCore
import CAMCore
import SwiftUI

/// Hosts the 3D material-removal simulation (Sources/KerfApp/Preview/) for the document's
/// enabled, calculated toolpaths. The 2D overlay is drawn by the design canvas itself.
struct Preview3DHost: View {
    @ObservedObject var document: KerfDocument
    @AppStorage(GCodeExporter.groupByToolKey) private var groupByTool = false

    /// Enabled, calculated toolpaths in machining order.
    var toolpaths: [Toolpath] {
        GCodeExporter.toolpaths(scope: .all, operations: document.outputProject.operations, results: document.results,
                                groupByTool: groupByTool)
    }

    var body: some View {
        SimulationPreviewView(
            job: document.outputProject.document.job, units: document.document.units, toolpaths: toolpaths,
            rapidRate: SimulationPreviewView.rapidRate(for: document.postProfile, units: document.document.units))
    }
}
