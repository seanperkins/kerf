import Foundation

/// SVG import: path/rect/circle/ellipse/line/polyline/polygon, transforms, viewBox + physical units.
public struct SVGImporter: VectorImporter {
    public static let fileExtensions = ["svg"]
    public init() {}

    public func importVectors(from data: Data, targetUnits: LengthUnit) throws -> ImportResult {
        // TODO(cad-io): implement.
        throw KerfIOError.notImplemented("SVGImporter")
    }
}
