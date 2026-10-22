import Foundation
import Testing
@testable import CADCore

@Suite struct IOSVGImportTests {
    let mm: ImportResult
    let px: ImportResult

    init() throws {
        mm = try SVGImporter().importVectors(from: IOFixtures.data("inkscape-mm.svg"), targetUnits: .millimeter)
        px = try SVGImporter().importVectors(from: IOFixtures.data("paths-px.svg"), targetUnits: .inch)
    }

    func shape(_ r: ImportResult, _ name: String) throws -> Shape {
        try #require(r.shapes.first { $0.name == name })
    }

    @Test func groupsBecomeLayersAndHiddenContentIsSkipped() throws {
        #expect(mm.layers.map(\.name) == ["SVG Import", "Outline", "Holes"])
        #expect(mm.shapes.count == 6) // border, hole1, <use> dot, oval, loose line, text outlines
        let holes = mm.layers[2].id
        #expect(mm.shapes.filter { $0.layerID == holes }.count == 3)
        #expect(mm.shapes.contains { $0.name == "ignored" && $0.paths.count > 3 })
        #expect(mm.shapes.allSatisfy { $0.origin == .imported(format: "svg") })
    }

    @Test func viewBoxPhysicalUnitsAndYFlip() throws {
        #expect(approx(try shape(mm, "border").bounds(), Rect2(x: 0, y: 0, width: 100, height: 50)))
        let hole = try shape(mm, "hole1").bounds()
        #expect(approx(hole, Rect2(x: 5, y: 35, width: 10, height: 10), 1e-3))
        let loose = try shape(mm, "loose")
        #expect(loose.paths[0].start.isApproximatelyEqual(to: Vec2(0, 0), tolerance: 1e-9))
        #expect(loose.paths[0].end.isApproximatelyEqual(to: Vec2(100, 50), tolerance: 1e-9))
        #expect(!loose.isClosed)
    }

    @Test func circlesStayArcsUnderConformalTransforms() throws {
        let hole = try shape(mm, "hole1")
        #expect(hole.paths[0].segments.allSatisfy { if case .arc = $0 { return true }; return false })
    }

    @Test func useAndNestedTransformsCompose() throws {
        let dot = try shape(mm, "dot")
        #expect(approx(dot.bounds(), Rect2(x: 28, y: 38, width: 4, height: 4), 1e-3))
        let oval = try shape(mm, "oval").bounds()
        #expect(approx(oval, Rect2(x: 42, y: 26, width: 16, height: 8), 1e-3))
    }

    @Test func importsIntoInches() throws {
        let r = try SVGImporter().importVectors(from: IOFixtures.data("inkscape-mm.svg"), targetUnits: .inch)
        let b = try shape(r, "border").bounds()
        #expect(approx(b.width, 100 / 25.4) && approx(b.height, 50 / 25.4))
    }

    @Test func pixelUnitsDefaultTo96PerInch() throws {
        let tri = try shape(px, "tri")
        #expect(tri.isClosed)
        #expect(approx(tri.bounds(), Rect2(x: 0, y: 0, width: 1, height: 1)))
        #expect(approx(abs(tri.paths[0].signedArea()), 0.5))
    }

    @Test func relativeCommandsAndMultipleSubpaths() throws {
        let rel = try shape(px, "rel")
        #expect(rel.paths.count == 2 && rel.isClosed)
        #expect(approx(rel.paths[1].bounds(), Rect2(min: Vec2(140, 96 - 30) / 96, max: Vec2(150, 96 - 10) / 96)))
    }

    @Test func quadraticsAndSmoothCurvesBecomeCubics() throws {
        let c = try shape(px, "curves").paths[0]
        #expect(c.segments.count == 4)
        #expect(c.segments.allSatisfy { if case .cubic = $0 { return true }; return false })
        #expect(c.end.isApproximatelyEqual(to: Vec2(180, 96 - 70) / 96, tolerance: 1e-9))
        // Reflected T control point keeps the curve symmetric: 140..180 hump goes down (Y-up: below 16/96).
        #expect(c.bounds(tolerance: 1e-5).min.y < (96 - 80) / 96.0 - 0.05)
    }

    @Test func circularArcFollowsSweepFlag() throws {
        let a = try shape(px, "arc").paths[0]
        #expect(a.segments.allSatisfy { if case .arc = $0 { return true }; return false })
        let b = a.bounds(tolerance: 1e-6)
        #expect(approx(b.min.y, 26 / 96, 1e-5) && approx(b.max.y, 46 / 96, 1e-5))
    }

    @Test func rotatedEllipticalArcHitsEndpoints() throws {
        let e = try shape(px, "earc").paths[0]
        #expect(e.start.isApproximatelyEqual(to: Vec2(10, 56) / 96, tolerance: 1e-9))
        #expect(e.end.isApproximatelyEqual(to: Vec2(50, 56) / 96, tolerance: 1e-9))
    }

    @Test func polygonsAndPolylines() throws {
        #expect(try shape(px, "poly").isClosed)
        let pl = try shape(px, "pl")
        #expect(!pl.isClosed && pl.paths[0].segments.count == 2)
    }

    @Test func illustratorStyleFileWithDoctypeAndPointUnits() throws {
        let r = try SVGImporter().importVectors(from: IOFixtures.data("illustrator-pt.svg"), targetUnits: .inch)
        #expect(r.layers.map(\.name) == ["Artwork"])
        #expect(r.shapes.count == 2 && r.shapes.allSatisfy { $0.isClosed })
        // 144pt = 2in across 192 user units.
        #expect(approx(r.shapes[0].bounds(), Rect2(x: 0, y: 0, width: 1, height: 1), 1e-6))
        #expect(approx(r.shapes[1].bounds(tolerance: 1e-6).max.x, 2, 1e-4))
    }

    @Test func malformedInputThrows() {
        #expect(throws: KerfIOError.self) {
            try SVGImporter().importVectors(from: Data("<html/>".utf8), targetUnits: .inch)
        }
        #expect(throws: KerfIOError.self) {
            try SVGImporter().importVectors(from: Data("not xml".utf8), targetUnits: .inch)
        }
    }
}

@Suite struct IOSVGParserTests {
    @Test func compactNumberSyntax() {
        let p = SVGPathParser.parse("M1.5.5L-1-2l.5e1,0")
        #expect(p.count == 1)
        #expect(p[0].start == Vec2(1.5, 0.5))
        #expect(p[0].segments == [.line(to: Vec2(-1, -2)), .line(to: Vec2(4, -2))])
    }

    @Test func packedArcFlags() {
        let p = SVGPathParser.parse("M0 0a5 5 0 0110 0")
        #expect(p.count == 1)
        #expect(p[0].end.isApproximatelyEqual(to: Vec2(10, 0), tolerance: 1e-9))
    }

    @Test func implicitLinetoAfterMoveto() {
        let p = SVGPathParser.parse("M0 0 10 0 10 10z")
        #expect(p[0].segments.count == 2 && p[0].isClosed)
    }

    @Test func stopsAtFirstErrorKeepingParsedGeometry() {
        let p = SVGPathParser.parse("M0 0 L10 0 L5 # 7")
        #expect(p.count == 1 && p[0].segments.count == 1)
    }

    @Test func transformListOrder() {
        let t = SVGAttributes.transform("translate(10, 0) scale(2)")
        #expect(t.apply(Vec2(1, 1)) == Vec2(12, 2))
        let r = SVGAttributes.transform("rotate(90 1 1)")
        #expect(r.apply(Vec2(2, 1)).isApproximatelyEqual(to: Vec2(1, 2), tolerance: 1e-12))
        let m = SVGAttributes.transform("matrix(1,0,0,1,3,4)")
        #expect(m.apply(.zero) == Vec2(3, 4))
    }

    @Test func lengthUnits() {
        #expect(SVGAttributes.pixels("1in", pixelsPerInch: 96) == 96)
        #expect(approx(SVGAttributes.pixels("25.4mm", pixelsPerInch: 96) ?? 0, 96))
        #expect(SVGAttributes.pixels("72pt", pixelsPerInch: 96) == 96)
        #expect(SVGAttributes.pixels("50%", percentOf: 200, pixelsPerInch: 96) == 100)
    }
}

@Suite struct IOSVGExportTests {
    let layer = Layer(name: "Cut & Drill", colorHex: "#FF0000")

    func roundTrip(_ shapes: [Shape], units: LengthUnit) throws -> ImportResult {
        let data = try SVGExporter().export(shapes: shapes, layers: [layer], units: units)
        return try SVGImporter().importVectors(from: data, targetUnits: units)
    }

    @Test func roundTripPreservesGeometryAndLayers() throws {
        let shapes = [
            Shape(name: "rr", layerID: layer.id, paths: [ShapeFactory.rectangle(Rect2(x: 1, y: 2, width: 6, height: 3), cornerRadius: 0.5)]),
            Shape(name: "c", layerID: layer.id, paths: [ShapeFactory.circle(center: Vec2(10, 5), radius: 2)]),
            Shape(name: "e", layerID: layer.id, paths: [ShapeFactory.ellipse(center: Vec2(4, 8), rx: 2, ry: 1)]),
            Shape(name: "open", layerID: layer.id, paths: [Path(points: [Vec2(0, 0), Vec2(3, 1)], closed: false)]),
        ]
        let r = try roundTrip(shapes, units: .inch)
        #expect(r.layers.map(\.name) == ["Cut & Drill"])
        #expect(r.shapes.count == 4)
        for (a, b) in zip(shapes, r.shapes) {
            #expect(approx(a.bounds(tolerance: 1e-5), b.bounds(tolerance: 1e-5), 1e-4))
            #expect(a.isClosed == b.isClosed)
            #expect(approx(a.paths[0].signedArea(tolerance: 1e-5), b.paths[0].signedArea(tolerance: 1e-5), 1e-4))
        }
        // Arcs survive as arcs.
        #expect(r.shapes[1].paths[0].segments.allSatisfy { if case .arc = $0 { return true }; return false })
    }

    @Test func clockwiseArcRoundTrips() throws {
        let p = Path(start: Vec2(0, 0), segments: [.arc(to: Vec2(4, 0), center: Vec2(2, 0), clockwise: true)])
        let r = try roundTrip([Shape(layerID: layer.id, paths: [p])], units: .millimeter)
        let b = r.shapes[0].bounds(tolerance: 1e-6)
        #expect(approx(b.max.y, 2, 1e-4)) // CW from (0,0) to (4,0) about (2,0) goes over the top
    }

    @Test func headerHasPhysicalSize() throws {
        let s = Shape(layerID: layer.id, paths: [ShapeFactory.rectangle(Rect2(x: 0, y: 0, width: 20, height: 10))])
        let text = String(decoding: try SVGExporter().export(shapes: [s], layers: [layer], units: .millimeter), as: UTF8.self)
        #expect(text.contains("width=\"20mm\"") && text.contains("height=\"10mm\""))
        #expect(text.contains("Cut &amp; Drill"))
    }
}

@Test func svgPathReturningToStartWithoutZImportsClosed() throws {
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><path d="M10 10 L 50 10 L50 50 L10 10"/><path d="M0 0 L5 5"/></svg>"#
    let r = try SVGImporter().importVectors(from: Data(svg.utf8), targetUnits: .inch)
    #expect(r.shapes.count == 2)
    #expect(r.shapes[0].isClosed)
    #expect(!r.shapes[1].isClosed)
}
