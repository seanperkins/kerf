import Foundation

/// The design: layers, shapes, 3D models, job setup. CAM operations live in
/// `KerfProject` (CAMCore), which wraps a `Document`.
public struct Document: Codable, Hashable, Sendable {
    public var name: String
    public var units: LengthUnit
    public var job: JobSetup
    public var layers: [Layer]
    public var shapes: [Shape]
    public var models: [PlacedModel]
    /// Grid spacing for snapping, in document units.
    public var gridSpacing: Double
    /// Areas toolpaths must avoid (clamps); nil = none (toolpaths-2d addition).
    public var keepOutZones: [KeepOutZone]?
    /// Raster tracing images; nil when there are none (see `placedImages`).
    public var images: [PlacedImage]?
    /// Multi-sheet jobs (see `MaterialSheet.swift`): id/name of the sheet whose setup is in
    /// `job` (nil = the primary sheet), the parked sheets, and their creation order.
    public var activeSheetID: UUID?
    public var activeSheetName: String?
    public var otherSheets: [MaterialSheet]?
    public var sheetOrder: [UUID]?
    /// Named numbers for numeric fields (see `ExpressionEvaluator`); nil when none.
    public var variables: [DocumentVariable]?

    public init(name: String = "Untitled", units: LengthUnit = .inch, job: JobSetup? = nil,
                layers: [Layer]? = nil, shapes: [Shape] = [], models: [PlacedModel] = [],
                gridSpacing: Double? = nil) {
        self.name = name
        self.units = units
        self.job = job ?? JobSetup.defaults(for: units)
        self.layers = layers ?? [Layer(name: "Layer 1")]
        self.shapes = shapes
        self.models = models
        self.gridSpacing = gridSpacing ?? (units == .inch ? 0.25 : 5)
    }

    public var defaultLayerID: UUID { layers[0].id }

    public func shape(id: UUID) -> Shape? { shapes.first { $0.id == id } }
    public func shapes(ids: [UUID]) -> [Shape] { ids.compactMap { shape(id: $0) } }
    public func shapes(inLayer layerID: UUID) -> [Shape] { shapes.filter { $0.layerID == layerID } }
    public func layer(id: UUID) -> Layer? { layers.first { $0.id == id } }
    public func model(id: UUID) -> PlacedModel? { models.first { $0.id == id } }

    public mutating func add(_ shape: Shape) { shapes.append(shape) }
    public mutating func removeShapes(ids: Set<UUID>) { shapes.removeAll { ids.contains($0.id) } }
    public mutating func replace(_ shape: Shape) {
        if let i = shapes.firstIndex(where: { $0.id == shape.id }) { shapes[i] = shape }
    }

    public var bounds: Rect2 { shapes.reduce(Rect2.empty) { $0.union($1.bounds()) } }
}
