import CADCore
import CAMCore
import PostCore
import SwiftUI

/// Placeholder main window. The app-shell workstream replaces this with the real layout
/// (toolbar, canvas, design/toolpath side panels, preview).
struct ContentView: View {
    @State private var document = Document()

    var body: some View {
        VStack(spacing: 12) {
            Text("Kerf").font(.largeTitle.bold())
            Text("CAD/CAM for the Avid PRO6096")
                .foregroundStyle(.secondary)
            Text("Material: \(fmt(document.job.width)) x \(fmt(document.job.height)) x \(fmt(document.job.thickness)) \(document.units.abbreviation)")
            Text("Post: \(BuiltInPosts.avidMach4Inch.name)")
                .font(.caption)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fmt(_ v: Double) -> String { String(format: "%g", v) }
}
