import Foundation
import Testing
@testable import CADCore

@Suite struct IOEPSTests {
    @Test func importsPathsRelativeToBoundingBox() throws {
        let r = try EPSImporter().importVectors(from: IOFixtures.data("simple.eps"), targetUnits: .inch)
        #expect(r.shapes.count == 2)
        #expect(r.warnings.isEmpty)
        let square = r.shapes[0]
        #expect(square.isClosed)
        #expect(approx(square.bounds(), Rect2(x: 0, y: 0, width: 1, height: 1)))
        let circle = r.shapes[1]
        #expect(circle.isClosed && circle.paths[0].segments.count == 4)
        #expect(approx(circle.bounds(tolerance: 1e-5), Rect2(x: 1, y: 0, width: 1, height: 1), 1e-3))
    }

    @Test func millimetres() throws {
        let r = try EPSImporter().importVectors(from: IOFixtures.data("simple.eps"), targetUnits: .millimeter)
        #expect(approx(r.shapes[0].bounds().width, 25.4))
    }

    @Test func rejectsPDFBasedAI() {
        #expect(throws: KerfIOError.self) {
            try EPSImporter().importVectors(from: Data("%PDF-1.5\n".utf8), targetUnits: .inch)
        }
    }

    @Test func registryFindsImporters() {
        #expect(FileFormats.importer(forExtension: "SVG") is SVGImporter)
        #expect(FileFormats.importer(forExtension: "dxf") is DXFImporter)
        #expect(FileFormats.importer(forExtension: "eps") is EPSImporter)
        #expect(FileFormats.importer(forExtension: "png") == nil)
    }
}
