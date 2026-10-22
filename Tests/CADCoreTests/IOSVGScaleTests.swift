import Foundation
import Testing
@testable import CADCore

/// An SVG with no physical size has user units whose length depends on the program that wrote it:
/// Inkscape 0.91 and older use 90 per inch, Illustrator 72, the web 96. Each fixture draws the same
/// 3 in square on a Letter or A4 page.
@Suite struct IOSVGScaleTests {
    static let generators = ["inkscape-091-px.svg", "inkscape-1x-mm.svg", "illustrator-px.svg", "coreldraw-in.svg"]

    func square(_ file: String, importer: SVGImporter = SVGImporter(), units: LengthUnit = .inch) throws -> (bounds: Rect2, result: ImportResult) {
        let r = try importer.importVectors(from: IOFixtures.data(file), targetUnits: units)
        let s = try #require(r.shapes.first { $0.name == "square" })
        return (s.bounds(), r)
    }

    @Test(arguments: generators)
    func theSameDrawingHasTheSamePhysicalSizeFromEveryProgram(file: String) throws {
        let b = try square(file).bounds
        #expect(approx(b.width, 3, 1e-4) && approx(b.height, 3, 1e-4), Comment(rawValue: "\(file): \(b.width) x \(b.height) in"))
        let mm = try square(file, units: .millimeter).bounds
        #expect(approx(mm.width, 76.2, 1e-3), Comment(rawValue: "\(file): \(mm.width) mm"))
    }

    @Test func thePageStaysTheReferenceForPlacement() throws {
        // The page's lower-left corner is (0, 0): the Letter page files put the square 0.5 in in from the
        // left and 0.5 in down from the top (y = 11 - 3 - 0.5).
        let ai = try square("illustrator-px.svg").bounds
        #expect(approx(ai.min.x, 0.5, 1e-4) && approx(ai.min.y, 7.5, 1e-4))
        let corel = try square("coreldraw-in.svg").bounds
        #expect(approx(corel.min.x, 0.5, 1e-4) && approx(corel.min.y, 7.5, 1e-4))
        let ink091 = try square("inkscape-091-px.svg").bounds
        #expect(approx(ink091.min.x, 100.0 / 90, 1e-4) && approx(ink091.min.y, 1052.3622047 / 90 - 370.0 / 90, 1e-4))
        let ink1x = try square("inkscape-1x-mm.svg").bounds
        #expect(approx(ink1x.min.x, 26.458333 / 25.4, 1e-4) && approx(ink1x.min.y, (297 - 26.458333 - 76.2) / 25.4, 1e-4))
    }

    @Test func scaleGuessNamesTheProgramAndTheUnitsItAssumes() throws {
        let ink091 = try #require(try SVGImporter.scaleGuess(of: IOFixtures.data("inkscape-091-px.svg")))
        #expect(ink091.pixelsPerInch == 90 && ink091.generator == "Inkscape 0.91")
        let ai = try #require(try SVGImporter.scaleGuess(of: IOFixtures.data("illustrator-px.svg")))
        #expect(ai.pixelsPerInch == 72 && ai.generator == "Adobe Illustrator")
        // A physical size on the page and a viewBox fix the scale, whoever wrote the file: nothing to guess.
        for file in ["inkscape-1x-mm.svg", "coreldraw-in.svg", "inkscape-mm.svg", "illustrator-pt.svg"] {
            #expect(try SVGImporter.scaleGuess(of: IOFixtures.data(file)) == nil, Comment(rawValue: file))
        }
        let plain = try #require(try SVGImporter.scaleGuess(of: IOFixtures.data("paths-px.svg")))
        #expect(plain.pixelsPerInch == 96 && plain.generator == nil)
    }

    @Test func inkscapeVersionsFromTheFirstThatUses96() throws {
        func ppi(_ version: String) throws -> Double {
            let svg = #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" width="100" height="100" inkscape:version="\#(version)"/>"#
            return try SVGImporter.scaleGuess(of: Data(svg.utf8))?.pixelsPerInch ?? 0
        }
        #expect(try ppi("0.48.5 r10040") == 90 && ppi("0.91 r13725") == 90 && ppi("0.9") == 90)
        #expect(try ppi("0.92.4 (5da689c313, 2019-01-14)") == 96 && ppi("1.0") == 96 && ppi("1.2.2 (b0a8486541)") == 96)
        #expect(try ppi("nonsense") == 96)
    }

    @Test func aFileWithNoHintImportsAt96AndSaysSo() throws {
        let r = try SVGImporter().importVectors(from: IOFixtures.data("paths-px.svg"), targetUnits: .inch)
        let tri = try #require(r.shapes.first { $0.name == "tri" })
        #expect(approx(tri.bounds(), Rect2(x: 0, y: 0, width: 1, height: 1)))
        let note = try #require(r.warnings.first { $0.contains("physical size") })
        #expect(note.contains("96 px per inch"))
        #expect(r.warnings.count == 1)
    }

    @Test func aDetectedScaleIsReported() throws {
        let ai = try square("illustrator-px.svg").result
        #expect(ai.warnings.contains { $0.contains("72 px per inch") && $0.contains("Adobe Illustrator") })
        let ink = try square("inkscape-091-px.svg").result
        #expect(ink.warnings.contains { $0.contains("90 px per inch") && $0.contains("Inkscape 0.91") })
        // Nothing to report when the file states its size.
        #expect(try square("inkscape-1x-mm.svg").result.warnings.isEmpty)
        #expect(try square("coreldraw-in.svg").result.warnings.isEmpty)
    }

    @Test func aChosenScaleOverridesTheGuessAndIsNotQuestioned() throws {
        let (b, r) = try square("illustrator-px.svg", importer: SVGImporter(pixelsPerInch: 96))
        #expect(approx(b.width, 216.0 / 96, 1e-4))
        #expect(r.warnings.isEmpty)
        #expect(approx(try square("inkscape-091-px.svg", importer: SVGImporter(pixelsPerInch: 72)).bounds.width, 270.0 / 72, 1e-4))
    }

    @Test func aPhysicalSizeIgnoresTheChosenScale() throws {
        for file in ["inkscape-1x-mm.svg", "coreldraw-in.svg"] {
            for ppi in [72.0, 90, 96] {
                let b = try square(file, importer: SVGImporter(pixelsPerInch: ppi)).bounds
                #expect(approx(b.width, 3, 1e-4), Comment(rawValue: "\(file) at \(ppi)"))
            }
        }
    }

    @Test func aPhysicalPageWithoutAViewBoxStillCountsUserUnitsPerInch() throws {
        // Inkscape 0.91 wrote mm on the page and drew in 90-per-inch user units. The page height must
        // be physical too, or every shape lands off by the ratio of the two.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
             width="210mm" height="297mm" inkscape:version="0.91 r13725">
          <rect id="square" x="100" y="100" width="270" height="270"/>
        </svg>
        """
        let r = try SVGImporter().importVectors(from: Data(svg.utf8), targetUnits: .inch)
        let b = try #require(r.shapes.first).bounds()
        #expect(approx(b.width, 3, 1e-4))
        #expect(approx(b.min.y, 297 / 25.4 - 370.0 / 90, 1e-4))
        #expect(try SVGImporter.scaleGuess(of: Data(svg.utf8))?.pixelsPerInch == 90)
    }

    @Test func unitlessShapesRecordTheScaleAndPhysicalOnesDoNot() throws {
        let ai = try square("illustrator-px.svg").result.shapes
        #expect(ai.allSatisfy { $0.origin == .imported(format: "svg", pixelsPerInch: 72) })
        let chosen = try square("illustrator-px.svg", importer: SVGImporter(pixelsPerInch: 90)).result.shapes
        #expect(chosen.allSatisfy { $0.origin == .imported(format: "svg", pixelsPerInch: 90) })
        let mm = try square("inkscape-1x-mm.svg").result.shapes
        #expect(mm.allSatisfy { $0.origin == .imported(format: "svg") })
    }

    @Test func projectsSavedBeforeTheScaleWasRecordedStillOpen() throws {
        let old = Data(#"{"imported":{"format":"svg"}}"#.utf8)
        #expect(try JSONDecoder().decode(ShapeOrigin.self, from: old) == .imported(format: "svg"))
        let now = try JSONEncoder().encode(ShapeOrigin.imported(format: "svg"))
        #expect(!String(decoding: now, as: UTF8.self).contains("pixelsPerInch"))
        let withScale = try JSONEncoder().encode(ShapeOrigin.imported(format: "svg", pixelsPerInch: 72))
        #expect(try JSONDecoder().decode(ShapeOrigin.self, from: withScale) == .imported(format: "svg", pixelsPerInch: 72))
    }

    @Test func physicalLengthsInsideTheDrawingKeepTheirSizeAtAnyScale() throws {
        // A 2 in page, a 1 in square and a 90 px square: the inch square is an inch whatever the scale; the
        // pixel square is 90 px, which is 90/scale inches.
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="2in" height="2in">
          <rect id="inch" x="0.5in" y="0.5in" width="1in" height="1in"/>
          <rect id="px" x="0" y="0" width="90" height="90"/>
          <rect id="mm" x="0" y="0" width="25.4mm" height="12pt"/>
          <use href="#px" x="1in"/>
        </svg>
        """
        for scale in [72.0, 90, 96] {
            let r = try SVGImporter(pixelsPerInch: scale).importVectors(from: Data(svg.utf8), targetUnits: .inch)
            func box(_ name: String) throws -> Rect2 { try #require(r.shapes.first { $0.name == name }).bounds() }
            let inch = try box("inch"), px = try box("px"), mm = try box("mm")
            #expect(approx(inch.width, 1, 1e-6) && approx(inch.height, 1, 1e-6) && approx(inch.min.x, 0.5, 1e-6), Comment(rawValue: "\(scale)"))
            #expect(approx(px.width, 90 / scale, 1e-6), Comment(rawValue: "\(scale)"))
            #expect(approx(mm.width, 1, 1e-6) && approx(mm.height, 12.0 / 72, 1e-6), Comment(rawValue: "\(scale)"))
            // The page is 2 in whatever the scale, so the square drawn from the top-left sits where it should.
            #expect(approx(inch.min.y, 2 - 0.5 - 1, 1e-6), Comment(rawValue: "\(scale)"))
        }
    }

    @Test func fontSizesInPointsAreWorthTheirPointsAtAnyScale() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="600" height="300">
          <text id="t" x="0" y="200" style="font-family:Helvetica; font-size:72pt">H</text>
        </svg>
        """
        // 72 pt is an inch, so a capital H is about 0.72 in tall at any scale.
        for scale in [72.0, 96] {
            let r = try SVGImporter(pixelsPerInch: scale).importVectors(from: Data(svg.utf8), targetUnits: .inch)
            let h = try #require(r.shapes.first).bounds().height
            #expect(h > 0.65 && h < 0.78, Comment(rawValue: "\(scale): \(h) in"))
        }
    }

    @Test func onlyRealPhysicalUnitsFixASize() throws {
        for good in ["1in", "25.4mm", "2.54cm", "72pt", "6pc", " 5MM ", "3 cm"] {
            #expect(SVGAttributes.hasPhysicalUnit(good), Comment(rawValue: good))
        }
        for bad in ["100vmin", "50%", "12", "12px", "2em", "", "mm", nil] as [String?] {
            #expect(!SVGAttributes.hasPhysicalUnit(bad), Comment(rawValue: bad ?? "nil"))
        }
        // A width of 100vmin states nothing about inches: the file still needs a scale.
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100vmin" height="100vmin" viewBox="0 0 10 10"/>"#
        #expect(try SVGImporter.scaleGuess(of: Data(svg.utf8)) != nil)
    }
}
