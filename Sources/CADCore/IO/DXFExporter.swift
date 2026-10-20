import Foundation

/// DXF (R12 ASCII) export: lines, arcs, splines flattened to polylines.
public struct DXFExporter: VectorExporter {
    public static let fileExtension = "dxf"
    public init() {}

    public func export(shapes: [Shape], layers: [Layer], units: LengthUnit) throws -> Data {
        // TODO(cad-io): implement.
        throw KerfIOError.notImplemented("DXFExporter")
    }
}
