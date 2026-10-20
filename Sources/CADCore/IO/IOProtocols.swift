import Foundation

public enum KerfIOError: Error, Equatable, Sendable {
    case notImplemented(String)
    case unsupportedFormat(String)
    case malformed(String)
}

/// Result of importing a vector file: new layers and the shapes assigned to them.
public struct ImportResult: Sendable {
    public var layers: [Layer]
    public var shapes: [Shape]
    public var warnings: [String]

    public init(layers: [Layer] = [], shapes: [Shape] = [], warnings: [String] = []) {
        self.layers = layers; self.shapes = shapes; self.warnings = warnings
    }
}

/// Imports 2D vector geometry. Implementations convert file units to `targetUnits`.
public protocol VectorImporter: Sendable {
    static var fileExtensions: [String] { get }
    func importVectors(from data: Data, targetUnits: LengthUnit) throws -> ImportResult
}

/// Exports shapes to a 2D vector file format.
public protocol VectorExporter: Sendable {
    static var fileExtension: String { get }
    func export(shapes: [Shape], layers: [Layer], units: LengthUnit) throws -> Data
}

/// Imports a triangle mesh (STL) for 3D toolpaths.
public protocol MeshImporter: Sendable {
    static var fileExtensions: [String] { get }
    func importMesh(from data: Data, targetUnits: LengthUnit) throws -> Mesh3D
}

/// Registry used by the app to pick an importer by file extension.
public enum FileFormats {
    public static let vectorImporters: [any VectorImporter.Type] = [SVGImporter.self, DXFImporter.self, EPSImporter.self, PDFImporter.self]
    public static let vectorExporters: [any VectorExporter.Type] = [SVGExporter.self, DXFExporter.self]

    public static func importer(forExtension ext: String) -> (any VectorImporter)? {
        let e = ext.lowercased()
        if SVGImporter.fileExtensions.contains(e) { return SVGImporter() }
        if DXFImporter.fileExtensions.contains(e) { return DXFImporter() }
        if EPSImporter.fileExtensions.contains(e) { return EPSImporter() }
        if PDFImporter.fileExtensions.contains(e) { return PDFImporter() }
        return nil
    }
}
