import CADCore
import SwiftUI

/// "Scale of file.svg": shown when an SVG does not state its size, so its units have to be read as pixels
/// at some number per inch. The scale the file's program is known to use is selected, and the size the
/// drawing comes out at is shown for the choice.
struct SVGScaleSheet: View {
    @ObservedObject var document: KerfDocument
    @Environment(\.dismiss) private var dismiss
    let request: SVGScaleRequest
    @State private var pixelsPerInch: Double
    @State private var size: Vec2?
    @State private var measured = false

    init(document: KerfDocument, request: SVGScaleRequest) {
        self.document = document
        self.request = request
        _pixelsPerInch = State(initialValue: request.info.pixelsPerInch)
    }

    private var why: String {
        if let program = request.info.generator {
            return "It looks like it came from \(program), which draws at \(Int(request.info.pixelsPerInch)) pixels per inch, so that is selected."
        }
        return "Nothing in the file says which program wrote it, so 96, the web default, is selected."
    }

    private var sizeText: String {
        guard measured else { return "Measuring…" }
        guard let size else { return "The file holds no vectors." }
        let u = document.units.abbreviation
        return "Comes in \(RulerTicks.label((size.x * 1000).rounded() / 1000)) × \(RulerTicks.label((size.y * 1000).rounded() / 1000)) \(u)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scale of \(request.fileName)").font(.title2.bold())
            Text("This SVG does not say how big it is, so its units are read as pixels at some number per inch. \(why)")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Pixels per inch", selection: $pixelsPerInch) {
                ForEach(SVGScaleRequest.choices, id: \.self) { Text("\(Int($0))").tag($0) }
            }
            .pickerStyle(.segmented)
            Text(sizeText).font(.body.monospacedDigit())
            Text("72: Adobe Illustrator and most design tools. 90: Inkscape 0.91 and older. 96: Inkscape 0.92 and newer, browsers and most other programs.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    document.importSVG(request, pixelsPerInch: pixelsPerInch)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task(id: pixelsPerInch) {
            measured = false
            let request = request, ppi = pixelsPerInch
            size = await Task.detached { request.drawingSize(at: ppi) }.value
            measured = true
        }
    }
}
