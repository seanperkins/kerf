import Foundation
import Testing
@testable import CADCore

/// Builds a minimal DXF from (code, value) pairs inside an ENTITIES section.
func dxf(header: [(Int, String)] = [], entities: [(Int, String)]) -> Data {
    var s = "0\nSECTION\n2\nHEADER\n"
    for (c, v) in header { s += "\(c)\n\(v)\n" }
    s += "0\nENDSEC\n0\nSECTION\n2\nENTITIES\n"
    for (c, v) in entities { s += "\(c)\n\(v)\n" }
    s += "0\nENDSEC\n0\nEOF\n"
    return Data(s.utf8)
}

@Suite struct IODXFImportTests {
    let r: ImportResult

    init() throws {
        r = try DXFImporter().importVectors(from: IOFixtures.data("mixed-mm.dxf"), targetUnits: .millimeter)
    }

    func shapes(_ layer: String) -> [Shape] {
        guard let id = r.layers.first(where: { $0.name == layer })?.id else { return [] }
        return r.shapes.filter { $0.layerID == id }
    }

    @Test func layersInFileOrderWithTableColours() {
        #expect(r.layers.map(\.name) == ["Square", "Holes", "Arcs", "Slot", "Poly", "Curves"])
        #expect(r.layers[0].colorHex == "#FF0000" && r.layers[1].colorHex == "#0000FF")
        #expect(r.warnings.contains { $0.contains("TEXT") })
        #expect(r.shapes.allSatisfy { $0.origin == .imported(format: "dxf") })
    }

    @Test func looseLinesJoinIntoClosedSquare() throws {
        let sq = shapes("Square")
        #expect(sq.count == 1)
        let p = try #require(sq.first?.paths.first)
        #expect(p.isClosed)
        #expect(approx(abs(p.signedArea()), 400))
    }

    @Test func circlesAndBlockInserts() {
        let holes = shapes("Holes")
        #expect(holes.count == 2)
        #expect(holes.contains { approx($0.bounds(), Rect2(x: 7, y: 7, width: 6, height: 6), 2e-3) })
        #expect(holes.contains { approx($0.bounds(), Rect2(x: 79.5, y: 79.5, width: 1, height: 1), 2e-3) })
    }

    @Test func arcIsCounterClockwise() throws {
        let a = try #require(shapes("Arcs").first?.paths.first)
        #expect(a.start.isApproximatelyEqual(to: Vec2(55, 0), tolerance: 1e-9))
        #expect(a.end.isApproximatelyEqual(to: Vec2(50, 5), tolerance: 1e-9))
        #expect(approx(a.length(tolerance: 1e-6), 5 * .pi / 2, 1e-4))
    }

    @Test func lwpolylineBulgesMakeSlot() throws {
        let p = try #require(shapes("Slot").first?.paths.first)
        #expect(p.isClosed)
        #expect(approx(p.bounds(tolerance: 1e-6), Rect2(x: 28, y: 0, width: 14, height: 4), 1e-5))
        #expect(approx(p.signedArea(tolerance: 1e-6), 40 + 4 * .pi, 1e-4))
    }

    @Test func oldStylePolyline() throws {
        let p = try #require(shapes("Poly").first?.paths.first)
        #expect(!p.isClosed && p.segments.count == 2 && p.end == Vec2(70, 10))
    }

    @Test func splineAndEllipse() throws {
        let curves = shapes("Curves")
        #expect(curves.count == 2)
        let spline = try #require(curves.first { !$0.isClosed }?.paths.first)
        #expect(spline.start.isApproximatelyEqual(to: Vec2(0, 30), tolerance: 1e-9))
        #expect(spline.end.isApproximatelyEqual(to: Vec2(30, 30), tolerance: 1e-9))
        #expect(approx(spline.bounds().max.y, 37.5, 1e-3))
        let ell = try #require(curves.first { $0.isClosed })
        #expect(approx(ell.bounds(tolerance: 1e-6), Rect2(x: 40, y: 25, width: 20, height: 10), 1e-3))
    }

    @Test func convertsToInches() throws {
        let r = try DXFImporter().importVectors(from: IOFixtures.data("mixed-mm.dxf"), targetUnits: .inch)
        let sq = try #require(r.shapes.first)
        #expect(approx(sq.bounds().width, 20 / 25.4))
    }

    @Test func inchHeaderAndUnitlessWarning() throws {
        let line: [(Int, String)] = [(0, "LINE"), (8, "0"), (10, "0"), (20, "0"), (11, "2"), (21, "0")]
        let inch = try DXFImporter().importVectors(from: dxf(header: [(9, "$INSUNITS"), (70, "1")], entities: line),
                                                   targetUnits: .millimeter)
        #expect(approx(inch.shapes[0].bounds().width, 50.8))
        let none = try DXFImporter().importVectors(from: dxf(entities: line), targetUnits: .inch)
        #expect(approx(none.shapes[0].bounds().width, 2))
        #expect(none.warnings.contains { $0.contains("no units") })
    }

    @Test func mirroredOCSArcFlipsX() throws {
        let arc: [(Int, String)] = [(0, "ARC"), (8, "0"), (10, "10"), (20, "0"), (40, "1"), (50, "0"), (51, "90"),
                                    (210, "0"), (220, "0"), (230, "-1")]
        let r = try DXFImporter().importVectors(from: dxf(entities: arc), targetUnits: .millimeter)
        let p = r.shapes[0].paths[0]
        #expect(p.start.isApproximatelyEqual(to: Vec2(-11, 0), tolerance: 1e-9))
        #expect(p.end.isApproximatelyEqual(to: Vec2(-10, 1), tolerance: 1e-9))
    }

    @Test func fitPointSplinePassesThroughPoints() throws {
        let sp: [(Int, String)] = [(0, "SPLINE"), (8, "0"), (70, "8"), (71, "3"), (74, "3"),
                                   (11, "0"), (21, "0"), (11, "5"), (21, "5"), (11, "10"), (21, "0")]
        let r = try DXFImporter().importVectors(from: dxf(entities: sp), targetUnits: .millimeter)
        let p = r.shapes[0].paths[0]
        #expect(p.segments.count == 2 && p.segments[0].end == Vec2(5, 5) && p.end == Vec2(10, 0))
    }

    @Test func lwpolylineReturningToStartWithoutClosedFlagImportsClosed() throws {
        let pl: [(Int, String)] = [(0, "LWPOLYLINE"), (8, "0"), (90, "4"), (70, "0"),
                                   (10, "0"), (20, "0"), (10, "4"), (20, "0"), (10, "2"), (20, "3"),
                                   (10, "0"), (20, "0")]
        let r = try DXFImporter().importVectors(from: dxf(entities: pl), targetUnits: .millimeter)
        #expect(r.shapes.count == 1 && r.shapes[0].isClosed)
    }

    @Test func rejectsGarbage() {
        #expect(throws: KerfIOError.self) { try DXFImporter().importVectors(from: Data("hello\nworld\n".utf8), targetUnits: .inch) }
    }
}

@Suite struct IODXFExportTests {
    let layer = Layer(name: "Profile: outside", colorHex: "#00FF00")

    @Test func roundTripPreservesGeometry() throws {
        let shapes = [
            Shape(layerID: layer.id, paths: [ShapeFactory.rectangle(Rect2(x: 1, y: 1, width: 4, height: 2), cornerRadius: 0.5)]),
            Shape(layerID: layer.id, paths: [ShapeFactory.circle(center: Vec2(8, 2), radius: 1)]),
            Shape(layerID: layer.id, paths: [ShapeFactory.ellipse(center: Vec2(3, 6), rx: 2, ry: 1)]),
            Shape(layerID: layer.id, paths: [Path(start: Vec2(10, 0), segments: [
                .line(to: Vec2(12, 0)), .arc(to: Vec2(12, 4), center: Vec2(12, 2), clockwise: true)])]),
        ]
        let data = try DXFExporter().export(shapes: shapes, layers: [layer], units: .inch)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("$INSUNITS") && text.contains("CIRCLE") && text.contains("Profile_ outside"))
        let r = try DXFImporter(joinTolerance: 0).importVectors(from: data, targetUnits: .inch)
        #expect(r.layers.map(\.name) == ["Profile_ outside"])
        #expect(r.layers[0].colorHex == "#00FF00")
        #expect(r.shapes.count == 4)
        for (a, b) in zip(shapes, r.shapes) {
            #expect(a.isClosed == b.isClosed)
            #expect(approx(a.bounds(tolerance: 1e-5), b.bounds(tolerance: 1e-5), 1e-3))
            #expect(approx(a.paths[0].signedArea(tolerance: 1e-5), b.paths[0].signedArea(tolerance: 1e-5), 1e-2))
        }
        // The CW arc keeps its direction (bulge sign).
        if case .arc(_, _, let cw) = r.shapes[3].paths[0].segments.last! { #expect(cw) } else { Issue.record("arc lost") }
    }

    @Test func millimetreHeader() throws {
        let s = Shape(layerID: layer.id, paths: [Path(points: [.zero, Vec2(1, 1)], closed: false)])
        let r = try DXFImporter().importVectors(from: DXFExporter().export(shapes: [s], layers: [layer], units: .millimeter),
                                                targetUnits: .inch)
        #expect(approx(r.shapes[0].bounds().width, 1 / 25.4))
    }
}
