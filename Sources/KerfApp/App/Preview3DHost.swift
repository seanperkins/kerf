import CADCore
import CAMCore
import SwiftUI

/// Hosts the 3D material-removal preview. The preview workstream owns the actual view
/// (Sources/KerfApp/Preview/); integration replaces the body below with it.
/// TODO(integration): show the preview workstream's 3D view here, fed with `job`/`toolpaths`.
struct Preview3DHost: View {
    @ObservedObject var document: KerfDocument

    /// Enabled, calculated toolpaths in machining order.
    var toolpaths: [Toolpath] {
        GCodeExporter.toolpaths(scope: .all, operations: document.project.operations, results: document.results,
                                groupByTool: false)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cube.transparent").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("3D Preview").font(.title2)
            Text("\(toolpaths.count) calculated toolpath(s) · estimated \(ToolpathCalculator.formatDuration(document.totalEstimatedSeconds))")
                .foregroundStyle(.secondary)
            Button("Back to 2D") { document.centerMode = .design2D }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
