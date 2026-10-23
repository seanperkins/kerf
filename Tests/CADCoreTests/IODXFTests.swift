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

    /// Issue #96. The spline sampling tolerance is a length in the document's units, whatever units the file is in.
    /// It used to be read in the file's own units, so a quarter circle of 100 mm radius in a metre drawing got 14
    /// samples (0.17 mm off the circle between them) where the same drawing in millimetres got 200 (0.001 mm).
    @Test(arguments: [(6, 0.001), (4, 1.0), (1, 1.0 / 25.4), (2, 1.0 / 304.8)])
    func splinesAreSampledWithinTheToleranceWhateverTheFileUnits(insunits: Int, unit: Double) throws {
        // Rational quadratic quarter circle of radius 100 mm, centred on the origin.
        let r = 100 * unit
        let w = 2.0.squareRoot() / 2
        let sp: [(Int, String)] = [(0, "SPLINE"), (8, "0"), (70, "8"), (71, "2"), (72, "6"), (73, "3"), (74, "0"),
                                   (40, "0"), (40, "0"), (40, "0"), (40, "1"), (40, "1"), (40, "1"),
                                   (41, "1"), (41, "\(w)"), (41, "1"),
                                   (10, "\(r)"), (20, "0"), (10, "\(r)"), (20, "\(r)"), (10, "0"), (20, "\(r)")]
        let res = try DXFImporter().importVectors(from: dxf(header: [(9, "$INSUNITS"), (70, "\(insunits)")], entities: sp),
                                                  targetUnits: .millimeter)
        let pts = res.shapes[0].paths[0].flattened(tolerance: 1e-6)
        #expect(pts.count > 8)
        // Between samples the chord falls short of the circle by its sagitta.
        var sag = 0.0
        for (a, b) in zip(pts, pts.dropFirst()) { sag = max(sag, 100 - ((a + b) / 2).length) }
        #expect(sag < 0.01, "the outline is \(sag) mm inside the circle between samples")
        #expect(abs(pts.first!.x - 100) < 1e-6 && abs(pts.last!.y - 100) < 1e-6)
    }

    @Test func lwpolylineReturningToStartWithoutClosedFlagImportsClosed() throws {
        let pl: [(Int, String)] = [(0, "LWPOLYLINE"), (8, "0"), (90, "4"), (70, "0"),
                                   (10, "0"), (20, "0"), (10, "4"), (20, "0"), (10, "2"), (20, "3"),
                                   (10, "0"), (20, "0")]
        let r = try DXFImporter().importVectors(from: dxf(entities: pl), targetUnits: .millimeter)
        #expect(r.shapes.count == 1 && r.shapes[0].isClosed)
    }

    // MARK: Gap report

    /// Four LINE entities on `layer` forming a 20-unit square whose last side stops `gap` short.
    func squareWithGap(_ gap: Double, layer: String = "Cabinet", x0: Double = 0) -> [(Int, String)] {
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> [(Int, String)] {
            [(0, "LINE"), (8, layer), (10, "\(x0 + x1)"), (20, "\(y1)"), (11, "\(x0 + x2)"), (21, "\(y2)")]
        }
        return line(0, 0, 20, 0) + line(20, 0, 20, 20) + line(20, 20, 0, 20) + line(0, 20, 0, gap)
    }

    func mm(_ entities: [(Int, String)], target: LengthUnit = .millimeter) throws -> ImportResult {
        try DXFImporter().importVectors(from: dxf(header: [(9, "$INSUNITS"), (70, target == .inch ? "1" : "4")],
                                                  entities: entities), targetUnits: target)
    }

    @Test func warnsWhenAnOutlineStopsJustShortOfClosing() throws {
        let r = try mm(squareWithGap(0.2))
        #expect(r.shapes.count == 1 && !r.shapes[0].isClosed)
        let note = try #require(r.warnings.first { $0.contains("nearly meet") })
        #expect(note.contains("Layer \"Cabinet\""))
        #expect(note.contains("1 open vector has ends"))
        #expect(note.contains("0.2 mm apart"))
        #expect(note.contains("joins ends within 0.01 mm"))
    }

    @Test func staysQuietWhenTheGapIsWithinTheJoinTolerance() throws {
        let r = try mm(squareWithGap(0.005))
        #expect(r.shapes.count == 1 && r.shapes[0].isClosed)
        #expect(!r.warnings.contains { $0.contains("nearly meet") })
    }

    @Test func staysQuietForALoneOpenLineAndForGapsTooBigToBeASlip() throws {
        let lone: [(Int, String)] = [(0, "LINE"), (8, "Engrave"), (10, "0"), (20, "0"), (11, "30"), (21, "0")]
        #expect(!(try mm(lone)).warnings.contains { $0.contains("nearly meet") })
        #expect(!(try mm(squareWithGap(2))).warnings.contains { $0.contains("nearly meet") })
    }

    @Test func reportsEachLayerAndPluralizes() throws {
        let r = try mm(squareWithGap(0.2, layer: "Cabinet") + squareWithGap(0.4, layer: "Drawer", x0: 100)
            + squareWithGap(0.1, layer: "Drawer", x0: 200))
        let notes = r.warnings.filter { $0.contains("nearly meet") }
        #expect(notes.count == 2)
        let drawer = try #require(notes.first { $0.contains("Layer \"Drawer\"") })
        #expect(drawer.contains("2 open vectors have ends"))
        #expect(drawer.contains("0.1 to 0.4 mm apart"))
    }

    @Test func usesInchesWhenTheDocumentIsInInches() throws {
        let r = try mm(squareWithGap(0.004), target: .inch)
        let note = try #require(r.warnings.first { $0.contains("nearly meet") })
        #expect(note.contains("0.004 in apart"))
        #expect(note.contains("joins ends within 0.0005 in"))
    }

    @Test func fixtureOutlineWithAGapReportsItInEitherUnit() throws {
        let data = try IOFixtures.data("outline-with-gap.dxf")
        let mm = try DXFImporter().importVectors(from: data, targetUnits: .millimeter)
        #expect(mm.shapes.count == 1 && !mm.shapes[0].isClosed)
        #expect(mm.warnings.contains { $0.contains("Layer \"Cabinet\"") && $0.contains("0.2 mm apart") })
        let inch = try DXFImporter().importVectors(from: data, targetUnits: .inch)
        #expect(inch.warnings.contains { $0.contains("0.0079 in apart") && $0.contains("within 0.0005 in") })
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
