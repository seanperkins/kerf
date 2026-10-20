import Foundation
import Testing
@testable import CADCore

@Suite struct IOOBJTests {
    /// A 10 x 20 x 5 mm box written Y-up (Y is the height), with quads, v/vt/vn faces and a
    /// negative index.
    static let box = """
    # box
    o Box
    v 0 0 0
    v 10 0 0
    v 10 0 -20
    v 0 0 -20
    v 0 5 0
    v 10 5 0
    v 10 5 -20
    v 0 5 -20
    vt 0 0
    vn 0 1 0
    f 1 4 3 2
    f 5/1/1 6/1/1 7/1/1 8/1/1
    f 1 2 6 5
    f 2 3 7 6
    f 3 4 8 7
    f 4 1 5 -1
    """

    @Test func importsYUpBoxAsZUpInInches() throws {
        let m = try OBJImporter().importMesh(from: Data(Self.box.utf8), targetUnits: .millimeter)
        #expect(m.triangleCount == 12)
        #expect(m.vertices.count == 8)
        let b = try #require(m.bounds)
        #expect(abs(b.max.x - b.min.x - 10) < 1e-9)
        #expect(abs(b.max.y - b.min.y - 20) < 1e-9)
        #expect(abs(b.max.z - b.min.z - 5) < 1e-9)
        let inch = try OBJImporter().importMesh(from: Data(Self.box.utf8), targetUnits: .inch)
        #expect(abs(inch.bounds!.max.x - 10 / 25.4) < 1e-9)
    }

    @Test func zUpOption() throws {
        let m = try OBJImporter(yUp: false).importMesh(from: Data(Self.box.utf8), targetUnits: .millimeter)
        #expect(abs(m.bounds!.max.y - m.bounds!.min.y - 5) < 1e-9)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: KerfIOError.self) { try OBJImporter().importMesh(from: Data("v 0 0 0\n".utf8), targetUnits: .inch) }
        #expect(throws: KerfIOError.self) {
            try OBJImporter().importMesh(from: Data("v 0 0 0\nf 1 2 3\n".utf8), targetUnits: .inch)
        }
    }
}
