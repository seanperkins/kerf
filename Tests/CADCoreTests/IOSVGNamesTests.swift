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

    /// A shape whose random UUID happens to start with eight decimal digits (about 2 exports in 100) used to come
    /// back named "Hole-12345678", because an all-digit suffix reads as a date or revision to the importer.
    @Test func aShapeWhoseIDStartsWithEightDigitsKeepsItsName() throws {
        let layer = Layer(name: "Drill")
        let id = try #require(UUID(uuidString: "12345678-1234-1234-1234-123456789012"))
        let hole = Shape(id: id, name: "Hole", layerID: layer.id, paths: [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.125)])
        let data = try SVGExporter().export(shapes: [hole], layers: [layer], units: .inch)
        let result = try SVGImporter().importVectors(from: data, targetUnits: .inch)
        #expect(result.shapes.map(\.name) == ["Hole"])
    }

    @Test func everyExportedSuffixIsOneTheImporterDrops() {
        // All-digit prefixes (the failing case), all-letter ones, and a spread of random ones.
        var ids = ["00000000", "12345678", "99999999", "01234567", "abcdef01", "ffffffff"]
            .compactMap { UUID(uuidString: $0 + "-0000-0000-0000-000000000000") }
        ids += (0..<2000).map { _ in UUID() }
        for id in ids {
            let suffix = SVGExporter.hashSuffix(of: id)
            #expect(suffix.count == 8, Comment(rawValue: "\(id)"))
            #expect(SVGImporter.displayName(forID: "Part-" + suffix) == "Part", Comment(rawValue: "\(id) -> \(suffix)"))
        }
        // Different shapes still get different suffixes (the point of the suffix).
        let a = UUID(uuidString: "12345678-0000-0000-0000-000000000001")!, b = UUID(uuidString: "12345679-0000-0000-0000-000000000001")!
        #expect(SVGExporter.hashSuffix(of: a) != SVGExporter.hashSuffix(of: b))
    }

    /// A prefix turned into letters can land on another shape's unchanged prefix ("00000000" gives "a0000000"):
    /// the ids in one file must still be distinct, or a <use> would resolve to the wrong shape.
    @Test func idsInOneFileStayDistinctWhenTheMappedSuffixesClash() throws {
        let layer = Layer(name: "Drill")
        func shape(_ prefix: String) throws -> Shape {
            let id = try #require(UUID(uuidString: prefix + "-0000-0000-0000-000000000000"))
            return Shape(id: id, name: "Hole", layerID: layer.id, paths: [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.125)])
        }
        // 00000000 maps to a0000000, which is exactly the second shape's own suffix; 60000000 maps there too.
        let shapes = [try shape("00000000"), try shape("a0000000"), try shape("60000000"), try shape("a0000000")]
        let data = try SVGExporter().export(shapes: shapes, layers: [layer], units: .inch)
        let text = String(decoding: data, as: UTF8.self)
        let ids = text.components(separatedBy: "id=\"").dropFirst().compactMap { $0.split(separator: "\"").first.map(String.init) }
            .filter { $0.hasPrefix("Hole-") }
        #expect(ids.count == 4 && Set(ids).count == 4, Comment(rawValue: "\(ids)"))
        let result = try SVGImporter().importVectors(from: data, targetUnits: .inch)
        #expect(result.shapes.map(\.name) == ["Hole", "Hole", "Hole", "Hole"])
    }
}

