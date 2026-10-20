import Foundation

/// One stock sheet of a multi-sheet job. The sheet being worked on always lives in
/// `Document.job`; the others wait in `Document.otherSheets` with their own job setup.
public struct MaterialSheet: Codable, Hashable, Identifiable, Sendable {
    /// Id of the job's first sheet (the one every single-sheet document has).
    public static let primaryID = UUID(uuidString: "00000000-0000-4000-8000-5348454554FF")!

    public var id: UUID
    public var name: String
    public var job: JobSetup

    public init(id: UUID = UUID(), name: String, job: JobSetup) {
        self.id = id; self.name = name; self.job = job
    }
}

extension Document {
    /// Id of the sheet in `job` (primary when unset).
    public var currentSheetID: UUID { activeSheetID ?? MaterialSheet.primaryID }

    public var isMultiSheet: Bool { !(otherSheets ?? []).isEmpty }

    /// Every sheet in a stable order (primary first, then by creation), the current one included.
    public var allSheets: [MaterialSheet] {
        var all = (otherSheets ?? []) + [MaterialSheet(id: currentSheetID, name: currentSheetName, job: job)]
        let order = sheetOrder ?? []
        all.sort { a, b in
            let ia = a.id == MaterialSheet.primaryID ? -1 : (order.firstIndex(of: a.id) ?? Int.max)
            let ib = b.id == MaterialSheet.primaryID ? -1 : (order.firstIndex(of: b.id) ?? Int.max)
            return ia < ib
        }
        return all
    }

    public var currentSheetName: String { activeSheetName ?? "Sheet 1" }

    /// Sheet a layer belongs to.
    public func sheetID(ofLayer id: UUID) -> UUID { layer(id: id)?.sheetID ?? MaterialSheet.primaryID }

    public func sheetID(of shape: Shape) -> UUID { sheetID(ofLayer: shape.layerID) }

    /// Common sheet of some shapes (nil when they span sheets; current sheet when empty).
    public func sheetID(ofShapes ids: [UUID]) -> UUID? {
        let s = Set(shapes(ids: ids).map { sheetID(of: $0) })
        if s.count > 1 { return nil }
        return s.first ?? currentSheetID
    }

    /// Job setup of any sheet.
    public func job(ofSheet id: UUID) -> JobSetup? {
        if id == currentSheetID { return job }
        return otherSheets?.first { $0.id == id }?.job
    }

    /// Makes `id` the current sheet: its job moves into `job`, the old one is parked.
    public mutating func switchToSheet(_ id: UUID) {
        guard id != currentSheetID, let i = otherSheets?.firstIndex(where: { $0.id == id }),
              let target = otherSheets?[i] else { return }
        let parked = MaterialSheet(id: currentSheetID, name: currentSheetName, job: job)
        otherSheets![i] = parked
        job = target.job
        activeSheetID = target.id == MaterialSheet.primaryID ? nil : target.id
        activeSheetName = target.name
    }

    /// Adds a sheet (parked) and a first layer for it. Returns the new sheet id.
    @discardableResult
    public mutating func addSheet(name: String, job newJob: JobSetup, layerName: String, colorHex: String) -> UUID {
        if activeSheetName == nil { activeSheetName = currentSheetName }
        let sheet = MaterialSheet(name: name, job: newJob)
        otherSheets = (otherSheets ?? []) + [sheet]
        sheetOrder = (sheetOrder ?? []) + [sheet.id]
        var layer = Layer(name: layerName, colorHex: colorHex)
        layer.sheetID = sheet.id
        layers.append(layer)
        return sheet.id
    }

    /// Removes a parked sheet with its layers and shapes (the current sheet cannot be removed).
    /// Returns the removed shape ids.
    public mutating func removeSheet(_ id: UUID) -> Set<UUID> {
        guard id != currentSheetID, otherSheets?.contains(where: { $0.id == id }) == true else { return [] }
        let layerIDs = Set(layers.filter { ($0.sheetID ?? MaterialSheet.primaryID) == id }.map(\.id))
        let shapeIDs = Set(shapes.filter { layerIDs.contains($0.layerID) }.map(\.id))
        removeShapes(ids: shapeIDs)
        layers.removeAll { layerIDs.contains($0.id) }
        otherSheets?.removeAll { $0.id == id }
        sheetOrder?.removeAll { $0 == id }
        if otherSheets?.isEmpty == true { otherSheets = nil; sheetOrder = nil }
        return shapeIDs
    }
}
