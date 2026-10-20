import Foundation

/// Marks a layer as an extra sheet of material (created when nesting overflows).
public struct SheetSlot: Codable, Hashable, Sendable {
    /// Sheet number, 2 or more. Sheet 1 is every shape that is not on a sheet layer.
    public var number: Int
    /// Current translation of the layer's shapes from the material frame; zero means this
    /// sheet is the one on the material (the one that is machined).
    public var offset: Vec2

    public init(number: Int, offset: Vec2) { self.number = number; self.offset = offset }
}

/// Several sheets in one document. Exactly one sheet sits on the material at a time; the
/// others are parked beside it (to the right) where they can be seen and edited, and CAM
/// ignores parked shapes. Showing another sheet on the material swaps the positions.
public enum NestSheets {
    /// Horizontal gap between parked sheets.
    public static func gap(for job: JobSetup) -> Double { max(job.width, job.height) * 0.08 }

    /// Where sheet `m` sits while sheet `active` is on the material.
    public static func slotOffset(sheet m: Int, active a: Int, job: JobSetup) -> Vec2 {
        guard m != a else { return .zero }
        let index = m < a ? m : m - 1
        return Vec2(Double(index) * (job.width + gap(for: job)), 0)
    }

    public static func sheetLayers(in doc: Document) -> [Layer] {
        doc.layers.filter { $0.sheet != nil }.sorted { $0.sheet!.number < $1.sheet!.number }
    }

    public static func hasSheets(_ doc: Document) -> Bool { doc.layers.contains { $0.sheet != nil } }

    /// Sheet numbers in use: 1 plus every sheet layer's number.
    public static func numbers(in doc: Document) -> [Int] { [1] + sheetLayers(in: doc).map { $0.sheet!.number } }

    /// The sheet currently on the material.
    public static func activeSheet(in doc: Document) -> Int {
        sheetLayers(in: doc).first { $0.sheet!.offset == .zero }?.sheet!.number ?? 1
    }

    public static func layer(forSheet n: Int, in doc: Document) -> Layer? {
        doc.layers.first { $0.sheet?.number == n }
    }

    /// Layers whose shapes belong to sheet `n` (sheet 1: every non-sheet layer).
    public static func layerIDs(ofSheet n: Int, in doc: Document) -> Set<UUID> {
        if n == 1 { return Set(doc.layers.filter { $0.sheet == nil && $0.keepOut == nil }.map(\.id)) }
        return Set(doc.layers.filter { $0.sheet?.number == n }.map(\.id))
    }

    /// Current offset of sheet `n` from the material.
    public static func offset(ofSheet n: Int, in doc: Document) -> Vec2 {
        if n == 1 { return slotOffset(sheet: 1, active: activeSheet(in: doc), job: doc.job) }
        return layer(forSheet: n, in: doc)?.sheet?.offset ?? .zero
    }

    /// Shapes of sheet `n` moved into the material frame (for previews and job sheets).
    public static func shapes(onSheet n: Int, in doc: Document) -> [Shape] {
        let layers = layerIDs(ofSheet: n, in: doc)
        let back = Transform2D.translation(-offset(ofSheet: n, in: doc))
        return doc.shapes.filter { layers.contains($0.layerID) }.map { $0.transformed(back) }
    }

    /// Layers whose shapes are parked off the material (clamp / keep-out layers never move).
    public static func parkedLayerIDs(in doc: Document) -> Set<UUID> {
        guard hasSheets(doc) else { return [] }
        let a = activeSheet(in: doc)
        return Set(doc.layers.filter { $0.keepOut == nil }.map(\.id)).subtracting(layerIDs(ofSheet: a, in: doc))
    }

    /// The document as CAM sees it: parked sheets and clamp / keep-out zones removed.
    public static func activeDocument(_ doc: Document) -> Document {
        let parked = parkedLayerIDs(in: doc).union(Fixtures.keepOutLayerIDs(in: doc))
        guard !parked.isEmpty else { return doc }
        var d = doc
        d.shapes.removeAll { parked.contains($0.layerID) }
        return d
    }

    /// Puts sheet `n` on the material and parks every other sheet in order beside it.
    public static func activate(_ n: Int, in doc: inout Document) {
        guard numbers(in: doc).contains(n) else { return }
        let a = activeSheet(in: doc)
        guard a != n else { return }
        let job = doc.job
        var deltas: [UUID: Vec2] = [:]
        for m in numbers(in: doc) {
            let old = offset(ofSheet: m, in: doc)
            let new = slotOffset(sheet: m, active: n, job: job)
            for id in layerIDs(ofSheet: m, in: doc) { deltas[id] = new - old }
        }
        for i in doc.shapes.indices {
            if let d = deltas[doc.shapes[i].layerID], d != .zero {
                doc.shapes[i] = doc.shapes[i].transformed(.translation(d))
            }
        }
        for i in doc.layers.indices {
            if let s = doc.layers[i].sheet {
                doc.layers[i].sheet?.offset = slotOffset(sheet: s.number, active: n, job: job)
            }
        }
    }

    /// The layer for sheet `n` (2 or more), created parked in its slot if missing.
    @discardableResult
    public static func ensureLayer(forSheet n: Int, in doc: inout Document, colorHex: String = "#7A6A53") -> UUID {
        if let l = layer(forSheet: n, in: doc) { return l.id }
        let off = slotOffset(sheet: n, active: activeSheet(in: doc), job: doc.job)
        let l = Layer(name: "Sheet \(n)", colorHex: colorHex, sheet: SheetSlot(number: n, offset: off))
        doc.layers.append(l)
        return l.id
    }

    /// Removes sheet layers without shapes (the active sheet is kept).
    public static func removeEmptySheets(in doc: inout Document) {
        let used = Set(doc.shapes.map(\.layerID))
        doc.layers.removeAll { $0.sheet != nil && $0.sheet!.offset != .zero && !used.contains($0.id) }
    }
}
