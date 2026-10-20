import Foundation
import Testing
@testable import CADCore

@Test func documentRoundTripsThroughJSON() throws {
    var doc = Document(name: "Sign", units: .inch)
    doc.add(Shape(layerID: doc.defaultLayerID, paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: 1)],
                  origin: .circle(radius: 1)))
    doc.job.zZero = .spoilboard
    doc.job.xyOrigin = .center
    let data = try JSONEncoder().encode(doc)
    let back = try JSONDecoder().decode(Document.self, from: data)
    #expect(back == doc)
}

@Test func unitConversion() {
    #expect(LengthUnit.inch.convert(1, to: .millimeter) == 25.4)
    #expect(abs(LengthUnit.millimeter.convert(25.4, to: .inch) - 1) < 1e-12)
    let t = ToolLibrary.seeded.tools[0].converted(to: .millimeter)
    #expect(abs(t.diameter - 6.35) < 1e-9)
}

@Test func seededLibraryHasUniqueToolNumbersAndPersists() throws {
    let lib = ToolLibrary.seeded
    #expect(Set(lib.tools.map(\.number)).count == lib.tools.count)
    #expect(Set(ToolKind.allCases).isSubset(of: Set(lib.tools.map(\.kind))))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ToolLibraryStore(fileURL: dir.appendingPathComponent("tools.json"))
    #expect(try store.load() == lib) // missing file → seeded
    var edited = lib
    edited.tools[0].feedRate = 123
    try store.save(edited)
    #expect(try store.load() == edited)
    try? FileManager.default.removeItem(at: dir)
}

@Test func vBitGeometry() {
    let v = Tool(name: "90", kind: .vBit, diameter: 0.5, angle: 90, stepdown: 0.1, stepover: 0.01,
                 feedRate: 60, plungeRate: 20)
    #expect(abs(v.vWidth(atDepth: 0.1) - 0.2) < 1e-12)
    #expect(abs(v.vDepth(forWidth: 0.2) - 0.1) < 1e-12)
}
