import Foundation

/// EPS import (optional): simple PostScript path operators only.
public struct EPSImporter: VectorImporter {
    public static let fileExtensions = ["eps", "ai"]
    public init() {}

    public func importVectors(from data: Data, targetUnits: LengthUnit) throws -> ImportResult {
        // TODO(cad-io): implement.
        throw KerfIOError.notImplemented("EPSImporter")
    }
}
