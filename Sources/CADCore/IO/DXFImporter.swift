import Foundation

/// DXF (ASCII) import: LINE, ARC, CIRCLE, LWPOLYLINE (bulges), POLYLINE, SPLINE (approximated), $INSUNITS.
public struct DXFImporter: VectorImporter {
    public static let fileExtensions = ["dxf"]
    public init() {}

    public func importVectors(from data: Data, targetUnits: LengthUnit) throws -> ImportResult {
        // TODO(cad-io): implement.
        throw KerfIOError.notImplemented("DXFImporter")
    }
}
