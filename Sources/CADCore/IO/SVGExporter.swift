import Foundation

/// SVG export with physical width/height in document units.
public struct SVGExporter: VectorExporter {
    public static let fileExtension = "svg"
    public init() {}

    public func export(shapes: [Shape], layers: [Layer], units: LengthUnit) throws -> Data {
        // TODO(cad-io): implement.
        throw KerfIOError.notImplemented("SVGExporter")
    }
}
