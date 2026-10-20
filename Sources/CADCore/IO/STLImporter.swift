import Foundation

/// STL (binary + ASCII) import. Owned by the cam-3d workstream.
public struct STLImporter: MeshImporter {
    public static let fileExtensions = ["stl"]
    public init() {}

    public func importMesh(from data: Data, targetUnits: LengthUnit) throws -> Mesh3D {
        // TODO(cam-3d): implement binary + ASCII STL parsing, merge duplicate vertices.
        throw KerfIOError.notImplemented("STLImporter")
    }
}
