import CADCore
import Foundation
import Testing
@testable import KerfApp

/// File > Import of an SVG that does not state its size asks for the scale first, with the one the file's
/// program uses selected; a file that states its size imports at once.
@MainActor
@Suite struct IOSVGScaleImportTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/CADCore")

    func document() -> KerfDocument {
        KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
    }

    func url(_ name: String) -> URL { Self.fixtures.appendingPathComponent(name) }
    func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-4) -> Bool { abs(a - b) <= tolerance }

    /// The shapes imported by name, newest first (the document starts with two rectangles).
    func square(in doc: KerfDocument) -> Shape? { doc.project.document.shapes.last { $0.name == "square" } }

    func asked(_ doc: KerfDocument) -> SVGScaleRequest? {
        if case .io(.svgScale(let request))? = doc.sheet { return request }
        return nil
    }

    @Test func aFileThatStatesItsSizeIsNotAsked() throws {
        for name in ["inkscape-1x-mm.svg", "coreldraw-in.svg", "inkscape-mm.svg", "outline-with-gap.dxf"] {
            let data = try Data(contentsOf: url(name))
            #expect(ImportService.scaleRequest(data: data, fileName: name, units: .inch) == nil, Comment(rawValue: name))
        }
    }

    @Test func aSizelessFileIsAskedWithItsProgramsScaleSelected() throws {
        let ai = try #require(ImportService.scaleRequest(data: Data(contentsOf: url("illustrator-px.svg")),
                                                          fileName: "illustrator-px.svg", units: .inch))
        #expect(ai.info.pixelsPerInch == 72 && ai.info.generator == "Adobe Illustrator")
        let plain = try #require(ImportService.scaleRequest(data: Data(contentsOf: url("paths-px.svg")),
                                                             fileName: "paths-px.svg", units: .inch))
        #expect(plain.info.pixelsPerInch == 96 && plain.info.generator == nil)
        #expect(SVGScaleRequest.choices.contains(72) && SVGScaleRequest.choices.contains(90) && SVGScaleRequest.choices.contains(96))
    }

    @Test func theSheetShowsTheSizeTheChoiceGivesAndNothingIsImportedYet() throws {
        let doc = document()
        let before = doc.project.document.shapes.count
        doc.importFiles([url("illustrator-px.svg")])
        let ask = try #require(asked(doc))
        #expect(doc.project.document.shapes.count == before)
        // The drawing is a 216 px square: 3 in at 72 per inch, 2.25 in at 96.
        let at72 = try #require(ask.drawingSize(at: 72)), at96 = try #require(ask.drawingSize(at: 96))
        #expect(close(at72.x, 3) && close(at72.y, 3))
        #expect(close(at96.x, 2.25) && close(at96.y, 2.25))
    }

    @Test func confirmingTheScaleImportsAtItWithOneUndoStepAndNoQuestions() throws {
        let doc = document()
        doc.importFiles([url("illustrator-px.svg")])
        let ask = try #require(asked(doc))
        doc.importSVG(ask, pixelsPerInch: 90)
        let s = try #require(square(in: doc))
        #expect(close(s.bounds().width, 216.0 / 90, 1e-4))
        #expect(s.origin == .imported(format: "svg", pixelsPerInch: 90))
        #expect(doc.selection == [s.id])
        // The user chose, so the importer has no guess to report.
        #expect(doc.alert == nil && doc.deferredAlert == nil)
    }

    @Test func cancellingImportsNothingAndTheNextFileIsAsked() throws {
        let doc = document()
        let before = doc.project.document.shapes.count
        doc.importFiles([url("illustrator-px.svg"), url("inkscape-091-px.svg")])
        #expect(asked(doc)?.fileName == "illustrator-px.svg")
        doc.sheet = nil          // Cancel
        doc.sheetDismissed()
        #expect(asked(doc)?.fileName == "inkscape-091-px.svg")
        #expect(asked(doc)?.info.pixelsPerInch == 90)
        doc.sheet = nil
        doc.sheetDismissed()
        #expect(doc.sheet == nil && doc.project.document.shapes.count == before)
    }

    @Test func aFileThatStatesItsSizeImportsAtOnceBesideAQueuedOne() throws {
        let doc = document()
        doc.importFiles([url("illustrator-px.svg"), url("inkscape-1x-mm.svg")])
        #expect(asked(doc)?.fileName == "illustrator-px.svg")
        let s = try #require(square(in: doc))
        #expect(close(s.bounds().width, 3, 1e-4))      // the millimetre file, already in
        #expect(s.origin == .imported(format: "svg"))
    }
}
