import Foundation
import Testing
@testable import CADCore

@Suite struct IODAETests {
    /// A 1 x 2 x 0.5 in box (quads via polylist) inside a SketchUp-style component
    /// (library_nodes + instance_node) translated by (10, 0, 0) in, plus a loose triangle.
    static func box(up: String = "Z_UP") -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">
          <asset><unit name="inch" meter="0.0254"/><up_axis>\(up)</up_axis></asset>
          <library_geometries>
            <geometry id="boxg"><mesh>
              <source id="boxp"><float_array id="boxpa" count="24">
                0 0 0  1 0 0  1 2 0  0 2 0  0 0 0.5  1 0 0.5  1 2 0.5  0 2 0.5
              </float_array><technique_common><accessor source="#boxpa" count="8" stride="3"/></technique_common></source>
              <vertices id="boxv"><input semantic="POSITION" source="#boxp"/></vertices>
              <polylist count="6">
                <input semantic="VERTEX" source="#boxv" offset="0"/>
                <vcount>4 4 4 4 4 4</vcount>
                <p>0 3 2 1  4 5 6 7  0 1 5 4  1 2 6 5  2 3 7 6  3 0 4 7</p>
              </polylist>
            </mesh></geometry>
            <geometry id="trig"><mesh>
              <source id="trip"><float_array id="tripa" count="9">0 0 0 1 0 0 0 1 0</float_array>
                <technique_common><accessor source="#tripa" count="3" stride="3"/></technique_common></source>
              <vertices id="triv"><input semantic="POSITION" source="#trip"/></vertices>
              <triangles count="1">
                <input semantic="VERTEX" source="#triv" offset="0"/><input semantic="NORMAL" source="#n" offset="1"/>
                <p>0 0 1 0 2 0</p>
              </triangles>
            </mesh></geometry>
          </library_geometries>
          <library_nodes>
            <node id="comp"><instance_geometry url="#boxg"/></node>
          </library_nodes>
          <library_visual_scenes>
            <visual_scene id="scene">
              <node><translate>10 0 0</translate><instance_node url="#comp"/></node>
              <node><matrix>1 0 0 0  0 1 0 0  0 0 1 0  0 0 0 1</matrix><instance_geometry url="#trig"/></node>
            </visual_scene>
          </library_visual_scenes>
          <scene><instance_visual_scene url="#scene"/></scene>
        </COLLADA>
        """.utf8)
    }

    @Test func readsComponentsTransformsAndUnits() throws {
        let m = try DAEImporter().importMesh(from: Self.box(), targetUnits: .inch)
        #expect(m.triangleCount == 13)
        let b = try #require(m.bounds)
        #expect(abs(b.min.x) < 1e-9 && abs(b.max.x - 11) < 1e-9)
        #expect(abs(b.max.y - 2) < 1e-9 && abs(b.max.z - 0.5) < 1e-9)
        let mm = try DAEImporter().importMesh(from: Self.box(), targetUnits: .millimeter)
        #expect(abs(mm.bounds!.max.x - 11 * 25.4) < 1e-6)
    }

    @Test func yUpIsTurnedToZUp() throws {
        let m = try DAEImporter().importMesh(from: Self.box(up: "Y_UP"), targetUnits: .inch)
        let b = try #require(m.bounds)
        #expect(abs(b.max.z - b.min.z - 2) < 1e-9)   // the box's Y extent is now its height
    }

    @Test func rejectsNonCollada() {
        #expect(throws: LoftLineIOError.self) { try DAEImporter().importMesh(from: Data("<svg/>".utf8), targetUnits: .inch) }
    }
}
