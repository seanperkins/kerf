import Foundation
import Testing
@testable import CADCore

/// Square pyramid (base 10 x 10 mm, apex 5 mm) as 6 triangles: 4 sides + 2 base.
private let pyramid: [(Vec3, Vec3, Vec3)] = {
    let a = Vec3(0, 0, 0), b = Vec3(10, 0, 0), c = Vec3(10, 10, 0), d = Vec3(0, 10, 0), apex = Vec3(5, 5, 5)
    return [(a, b, apex), (b, c, apex), (c, d, apex), (d, a, apex), (a, c, b), (a, d, c)]
}()

private func binarySTL(_ tris: [(Vec3, Vec3, Vec3)], header: String = "binary test") -> Data {
    var d = Data(header.utf8.prefix(80))
    d.append(Data(repeating: 0, count: 80 - d.count))
    var n = UInt32(tris.count).littleEndian
    d.append(Data(bytes: &n, count: 4))
    func put(_ f: Float) { var b = f.bitPattern.littleEndian; d.append(Data(bytes: &b, count: 4)) }
    for (p, q, r) in tris {
        for _ in 0..<3 { put(0) } // normal (ignored)
        for v in [p, q, r] { put(Float(v.x)); put(Float(v.y)); put(Float(v.z)) }
        d.append(contentsOf: [0, 0])
    }
    return d
}

private func asciiSTL(_ tris: [(Vec3, Vec3, Vec3)]) -> Data {
    var s = "solid test\n"
    for (p, q, r) in tris {
        s += "  facet normal 0 0 0\n    outer loop\n"
        for v in [p, q, r] { s += "      vertex \(v.x) \(v.y) \(v.z)\n" }
        s += "    endloop\n  endfacet\n"
    }
    s += "endsolid test\n"
    return Data(s.utf8)
}

@Test func stlBinaryPyramidMergesVertices() throws {
    let mesh = try STLImporter().importMesh(from: binarySTL(pyramid), targetUnits: .millimeter)
    #expect(mesh.triangleCount == 6)
    #expect(mesh.vertices.count == 5)
    let b = try #require(mesh.bounds)
    #expect(b.max.z == 5)
    #expect(b.max.x == 10)
}

@Test func stlASCIIPyramidConvertsToInches() throws {
    let mesh = try STLImporter().importMesh(from: asciiSTL(pyramid), targetUnits: .inch)
    #expect(mesh.triangleCount == 6)
    #expect(mesh.vertices.count == 5)
    let b = try #require(mesh.bounds)
    #expect(abs(b.max.x - 10 / 25.4) < 1e-9)
}

@Test func stlBinaryWithSolidHeaderIsStillBinary() throws {
    let mesh = try STLImporter().importMesh(from: binarySTL(pyramid, header: "solid but binary"),
                                            targetUnits: .millimeter)
    #expect(mesh.triangleCount == 6)
}

@Test func stlRejectsGarbage() {
    #expect(throws: LoftLineIOError.self) {
        try STLImporter().importMesh(from: Data("hello world".utf8), targetUnits: .inch)
    }
    #expect(throws: LoftLineIOError.self) {
        try STLImporter().importMesh(from: Data("solid empty\nendsolid\n".utf8), targetUnits: .inch)
    }
}

@Test func stlDropsDegenerateTriangles() throws {
    let a = Vec3(0, 0, 0)
    let tris = pyramid + [(a, a, Vec3(1, 1, 1))]
    let mesh = try STLImporter().importMesh(from: binarySTL(tris), targetUnits: .millimeter)
    #expect(mesh.triangleCount == 6)
}
