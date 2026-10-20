import AppKit
import CADCore
import CAMCore
import Foundation
import SwiftUI
import Testing
@testable import KerfApp

@MainActor
@Test func gcodePreviewReadsTheSampleProgram() throws {
    let url = SampleFilesTests.samplesDir.appendingPathComponent("sign.tap")
    let text = try String(contentsOf: url, encoding: .utf8)
    let job = JobSetup(width: 24, height: 12, thickness: 0.75)
    let model = GCodePreviewModel(text: text, fileName: "sign.tap", units: .inch, job: job)
    // T1 pocket, T6 V-carve, T9 drill, T1 profile.
    #expect(model.tools.map(\.tool.number) == [1, 6, 9, 1])
    #expect(model.tools[1].tool.kind == .vBit)
    #expect(model.tools[2].tool.kind == .drill)
    #expect(model.reader.warnings.isEmpty)
    let tps = model.toolpaths
    #expect(tps.count == 4)
    let coords = MachineCoordinates(job: job)
    // The profile cuts through the 0.75" material (plus allowance) and nothing goes above the home Z.
    let deepest = tps.compactMap(\.minZ).min()!
    #expect(coords.depth(ofMachineZ: deepest) >= 0.75 - 1e-6)
    // Renders without crashing.
    let view = NSHostingView(rootView: GCodePreviewView(model: model, job: job, rapidRate: 300))
    view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
    view.layoutSubtreeIfNeeded()
    #expect(view.fittingSize.width > 0)
}

@Test func gcodePreviewUsesMillimetreDocumentsToo() {
    let text = "G20\nG90\nT3 M6\nS16000 M3\nG0 X1 Y1 Z0.2\nG1 Z-0.1 F20\nX2 F60\nG0 Z0.2\nM30\n"
    let job = JobSetup(width: 100, height: 100, thickness: 18)
    let model = GCodePreviewModel(text: text, fileName: "x.tap", units: .millimeter, job: job)
    #expect(model.tools.count == 1 && model.tools[0].tool.diameter == 6)
    let tp = model.toolpaths[0]
    #expect(abs((tp.minZ ?? 0) + 2.54) < 1e-9)
    #expect(tp.spindleRPM == 16000)
    #expect(model.summary.contains("inches"))
}
