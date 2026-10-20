import Foundation
import Testing
@testable import CADCore

@Suite struct IOMeshPartsTests {
    /// Axis-aligned box mesh (12 triangles, outward CCW).
    static func box(_ lo: Vec3, _ hi: Vec3) -> [(Vec3, Vec3, Vec3)] {
        let p = [Vec3(lo.x, lo.y, lo.z), Vec3(hi.x, lo.y, lo.z), Vec3(hi.x, hi.y, lo.z), Vec3(lo.x, hi.y, lo.z),
                 Vec3(lo.x, lo.y, hi.z), Vec3(hi.x, lo.y, hi.z), Vec3(hi.x, hi.y, hi.z), Vec3(lo.x, hi.y, hi.z)]
        let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        return quads.flatMap { q in [(p[q[0]], p[q[1]], p[q[2]]), (p[q[0]], p[q[2]], p[q[3]])] }
    }

    static func part(_ tris: [(Vec3, Vec3, Vec3)], name: String = "P") -> MeshPart {
        MeshPart(name: name, mesh: STLImporter.indexed(tris, scale: 1))
    }

    @Test func daePartsFollowSceneNodesAndComponentNames() throws {
        let parts = try DAEImporter().importParts(from: IODAETests.box(), targetUnits: .inch)
        #expect(parts.count == 2)
        #expect(parts[0].name == "comp")
        #expect(parts[0].mesh.triangleCount == 12)
        #expect(parts[1].name == "Part 2")
        #expect(parts[1].mesh.triangleCount == 1)
        // The whole-model import is unchanged.
        #expect(try DAEImporter().importMesh(from: IODAETests.box(), targetUnits: .inch).triangleCount == 13)
    }

    @Test func wrapperNodeIsUnwrapped() throws {
        let xml = String(decoding: IODAETests.box(), as: UTF8.self)
            .replacingOccurrences(of: "<visual_scene id=\"scene\">", with: "<visual_scene id=\"scene\"><node name=\"SketchUp\">")
            .replacingOccurrences(of: "</visual_scene>", with: "</node></visual_scene>")
        let parts = try DAEImporter().importParts(from: Data(xml.utf8), targetUnits: .inch)
        #expect(parts.count == 2)
    }

    @Test func flatOutlineLaysABoardOnItsFace() throws {
        // A 0.75 x 10 x 20 board standing on edge (its faces point along X).
        let board = Self.part(Self.box(Vec3(5, 0, 0), Vec3(5.75, 10, 20)))
        let o = try #require(MeshParts.outline(of: board, view: .flat))
        #expect(abs(o.thickness - 0.75) < 1e-9)
        let dims = [o.bounds.width, o.bounds.height].sorted()
        #expect(abs(dims[0] - 10) < 1e-9 && abs(dims[1] - 20) < 1e-9)
        #expect(abs(o.bounds.min.x) < 1e-9 && abs(o.bounds.min.y) < 1e-9)
        #expect(o.paths.count == 1)
        #expect(o.paths[0].flattened().count <= 5)   // a clean rectangle, no T-junction points
        // Seen from the top it is a thin strip.
        let top = try #require(MeshParts.outline(of: board, view: .top))
        #expect(abs(top.bounds.width - 0.75) < 1e-9 && abs(top.bounds.height - 10) < 1e-9)
        #expect(abs(top.thickness - 20) < 1e-9)
    }

    @Test func frontAndRightViews() throws {
        let b = Self.part(Self.box(.zero, Vec3(1, 2, 3)))
        let front = try #require(MeshParts.outline(of: b, view: .front))
        #expect(abs(front.bounds.width - 1) < 1e-9 && abs(front.bounds.height - 3) < 1e-9)
        let right = try #require(MeshParts.outline(of: b, view: .right))
        #expect(abs(right.bounds.width - 2) < 1e-9 && abs(right.bounds.height - 3) < 1e-9)
    }

    @Test func overlappingSolidsUnionAndHolesSurvive() throws {
        // A frame: four bars around a 2 x 2 opening, seen from above.
        let bars = Self.box(.zero, Vec3(4, 1, 1)) + Self.box(Vec3(0, 3, 0), Vec3(4, 4, 1))
            + Self.box(Vec3(0, 0, 0), Vec3(1, 4, 1)) + Self.box(Vec3(3, 0, 0), Vec3(4, 4, 1))
        let o = try #require(MeshParts.outline(of: Self.part(bars), view: .top))
        #expect(o.paths.count == 2)
        let areas = o.paths.map { abs($0.signedArea()) }.sorted()
        #expect(abs(areas[0] - 4) < 1e-6 && abs(areas[1] - 16) < 1e-6)
    }

    @Test func connectedComponentsSplitLooseSolids() {
        let mesh = STLImporter.indexed(Self.box(.zero, Vec3(1, 1, 1)) + Self.box(Vec3(3, 0, 0), Vec3(5, 1, 1)), scale: 1)
        let parts = MeshParts.connectedComponents(mesh, name: "chair")
        #expect(parts.count == 2)
        #expect(parts.map(\.name) == ["chair 1", "chair 2"])
        #expect(parts.allSatisfy { $0.mesh.triangleCount == 12 && $0.mesh.vertices.count == 8 })
        let one = MeshParts.connectedComponents(STLImporter.indexed(Self.box(.zero, Vec3(1, 1, 1)), scale: 1), name: "cube")
        #expect(one.map(\.name) == ["cube"])
    }

    @Test func shelfLayoutWrapsRows() {
        let offs = MeshParts.shelfOffsets([Vec2(10, 2), Vec2(10, 3), Vec2(10, 1)], origin: Vec2(0, 0), rowWidth: 21, gap: 0.5)
        #expect(offs[0] == Vec2(0, 0))
        #expect(offs[1] == Vec2(10.5, 0))
        #expect(offs[2] == Vec2(0, 3.5))
    }

    @Test func layoutPlacesFlatPartsInsideTheArea() {
        let parts = [Self.part(Self.box(.zero, Vec3(10, 20, 0.75)), name: "A"),
                     Self.part(Self.box(Vec3(30, 0, 0), Vec3(30.5, 8, 8)), name: "B")]
        let out = MeshParts.layout(parts, view: .flat, area: Rect2(x: 0, y: 0, width: 48, height: 96), gap: 0.5)
        #expect(out.count == 2)
        #expect(abs(out[0].bounds.min.x - 0.5) < 1e-9 && abs(out[0].bounds.min.y - 0.5) < 1e-9)
        #expect(out[1].bounds.min.x > out[0].bounds.max.x)
        #expect(abs(out[1].thickness - 0.5) < 1e-9)
    }
}
