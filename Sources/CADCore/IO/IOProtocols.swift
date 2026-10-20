import Foundation

public enum KerfIOError: Error, Equatable, Sendable {
    case notImplemented(String)
    case unsupportedFormat(String)
    case malformed(String)
}

/// A raster image found in a vector file (PDF image XObject, SVG `<image>`).
public struct ImportedImage: Sendable {
    /// Axis-aligned placement in document units (material frame).
    public var rect: Rect2
    /// PNG-encoded pixels.
    public var png: Data

    public init(rect: Rect2, png: Data) { self.rect = rect; self.png = png }
}

/// Result of importing a vector file: new layers and the shapes assigned to them.
public struct ImportResult: Sendable {
    public var layers: [Layer]
    public var shapes: [Shape]
    public var warnings: [String]
    /// Embedded raster images (the app places them as tracing images).
    public var images: [ImportedImage]

    public init(layers: [Layer] = [], shapes: [Shape] = [], warnings: [String] = [], images: [ImportedImage] = []) {
        self.layers = layers; self.shapes = shapes; self.warnings = warnings; self.images = images
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
    public static let vectorExporters: [any VectorExporter.Type] = [SVGExporter.self, DXFExporter.self, PDFExporter.self,
                                                                     EPSExporter.self]

    /// Exporter for a file extension; `.ai` is written as PDF (Illustrator opens PDF files).
    public static func exporter(forExtension ext: String) -> (any VectorExporter)? {
        switch ext.lowercased() {
        case "svg": return SVGExporter()
        case "dxf": return DXFExporter()
        case "pdf", "ai": return PDFExporter()
        case "eps": return EPSExporter()
        default: return nil
        }
    }

    public static func importer(forExtension ext: String) -> (any VectorImporter)? {
        let e = ext.lowercased()
        if SVGImporter.fileExtensions.contains(e) { return SVGImporter() }
        if DXFImporter.fileExtensions.contains(e) { return DXFImporter() }
        if EPSImporter.fileExtensions.contains(e) { return EPSImporter() }
        if PDFImporter.fileExtensions.contains(e) { return PDFImporter() }
        return nil
    }
}
