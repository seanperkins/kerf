import Foundation
import Testing
@testable import CADCore

/// Kerf's own SVG export gives each element an id "Name-<8 hex digits>" so ids stay unique; importing
/// that file must not leave the hash on the shape's name.
@Suite struct IOSVGNamesTests {
    @Test func theExportersHashSuffixIsDropped() {
        #expect(SVGImporter.displayName(forID: "Outline-5b61fcf9") == "Outline")
        #expect(SVGImporter.displayName(forID: "Hole-ad5805c2") == "Hole")
        #expect(SVGImporter.displayName(forID: "Mounting-hole-ad5805c2") == "Mounting-hole")
    }

    @Test func otherIDsAreLeftAlone() {
        #expect(SVGImporter.displayName(forID: "path4821") == "path4821")
        #expect(SVGImporter.displayName(forID: "my-part") == "my-part")
        // Not eight hex digits, or digits only (a date, a revision): keep it.
        #expect(SVGImporter.displayName(forID: "Part-5b61fc") == "Part-5b61fc")
        #expect(SVGImporter.displayName(forID: "Rev-20240101") == "Rev-20240101")
        // A bare hash would leave an empty name.
        #expect(SVGImporter.displayName(forID: "-5b61fcf9") == "-5b61fcf9")
    }

    @Test func aShapeSurvivesAnExportAndImportWithItsName() throws {
        let layer = Layer(name: "Drill")
        let hole = Shape(name: "Hole", layerID: layer.id, paths: [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.125)])
        let data = try SVGExporter().export(shapes: [hole], layers: [layer], units: .inch)
        let result = try SVGImporter().importVectors(from: data, targetUnits: .inch)
        #expect(result.shapes.map(\.name) == ["Hole"])
    }
}
