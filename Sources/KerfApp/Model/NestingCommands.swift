import CADCore
import CAMCore
import Foundation

/// Grid resolution for nesting (more cells = tighter packing, slower).
enum NestPrecision: String, CaseIterable, Identifiable {
    case draft, normal, fine
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var cells: Int {
        switch self {
        case .draft: return 250_000
        case .normal: return 1_000_000
        case .fine: return 3_000_000
        }
    }
}

/// Settings of Design > Nest Parts….
struct NestingOptions: Equatable {
    var spacing: Double
    var margin: Double
    /// Degrees; 0 = keep orientation.
    var rotationStep: Double = 90
    var nestInHoles = true
    /// Copies of every part (the originals count as the first copy).
    var quantity = 1
    var precision: NestPrecision = .normal
    /// Keep clear of vectors that are not being nested.
    var avoidOtherVectors = true

    static func defaults(for units: LengthUnit) -> NestingOptions {
        units == .inch ? NestingOptions(spacing: 0.375, margin: 0.25)
            : NestingOptions(spacing: 10, margin: 6)
    }

    func settings(for job: JobSetup, maxSheets: Int = 1) -> NestSettings {
        NestSettings(sheetWidth: job.width, sheetHeight: job.height, margin: max(0, margin),
                     spacing: max(0, spacing), rotationStep: rotationStep, nestInHoles: nestInHoles,
                     maxSheets: maxSheets, precision: precision.cells)
    }
}

/// Outcome of a nest, for the sheet's summary line.
struct NestingReport: Equatable {
    var parts: Int
    var placed: Int
    var unplaced: Int
    var sheets: Int
    var utilisation: [Double]
    /// Shapes of all placed parts (originals and new copies), for the new selection.
    var placedShapeIDs: [UUID]

    var summary: String {
        var s = "Placed \(placed) of \(placed + unplaced) part\(placed + unplaced == 1 ? "" : "s")"
        if sheets > 1 { s += " on \(sheets) sheets" }
        if !utilisation.isEmpty {
            s += " (" + utilisation.map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: ", ") + " of the material used)"
        }
        if unplaced > 0 { s += ". \(unplaced) did not fit and \(unplaced == 1 ? "was" : "were") left where \(unplaced == 1 ? "it was" : "they were") (or not created)." }
        return s
    }
}

enum NestingCommands {
    /// Nests the given shapes (grouped into parts by `NestPartBuilder`) on the material.
    /// Copies beyond the first are new shapes and are added to every toolpath that uses the
    /// original. Parts that do not fit stay where they are.
    static func nest(_ ids: [UUID], options: NestingOptions, in project: inout KerfProject) -> NestingReport {
        let doc = project.document
        let shapes = doc.shapes(ids: doc.expandToGroups(ids)).filter { project.isEditable($0) }
        let tol = doc.units == .inch ? 0.002 : 0.05
        let groups = NestPartBuilder.parts(from: shapes, tolerance: tol)
        guard !groups.isEmpty else {
            return NestingReport(parts: 0, placed: 0, unplaced: 0, sheets: 0, utilisation: [], placedShapeIDs: [])
        }
        let moving = Set(groups.flatMap(\.shapeIDs))
        var obstacles: [[Vec2]] = []
        if options.avoidOtherVectors {
            let others = doc.shapes.filter { !moving.contains($0.id) && project.isVisible($0) }
            for s in others { obstacles += NestPartBuilder.parts(from: [s], tolerance: tol).flatMap(\.outline) }
        }
        let parts = groups.map { NestPart(outline: $0.outline, quantity: max(1, options.quantity)) }
        let result = Nester.nest(parts, settings: options.settings(for: doc.job), firstSheetObstacles: obstacles)
        return apply(result, groups: groups, in: &project)
    }

    /// Moves originals / creates copies according to `result`.
    static func apply(_ result: NestResult, groups: [NestPartGroup], in project: inout KerfProject) -> NestingReport {
        var placedIDs: [UUID] = []
        // Copies are made from the shapes as they were before any part moved.
        let before = Dictionary(uniqueKeysWithValues: project.document.shapes.map { ($0.id, $0) })
        for pl in result.placements {
            let group = groups[pl.part]
            if pl.copy == 0 {
                project.transformShapes(Set(group.shapeIDs), by: pl.transform)
                placedIDs += group.shapeIDs
            } else {
                let originals = group.shapeIDs.compactMap { before[$0] }
                var groupMap: [UUID: UUID] = [:]
                var idMap: [UUID: UUID] = [:]
                for s in originals {
                    var c = s.transformed(pl.transform)
                    c.id = UUID()
                    if let g = s.groupID {
                        if groupMap[g] == nil { groupMap[g] = UUID() }
                        c.groupID = groupMap[g]
                    }
                    project.document.add(c)
                    idMap[s.id] = c.id
                    placedIDs.append(c.id)
                }
                addCopies(idMap, toOperationsOf: &project)
            }
        }
        return NestingReport(parts: groups.count, placed: result.placements.count, unplaced: result.unplacedCount,
                             sheets: result.sheetsUsed, utilisation: result.utilisation, placedShapeIDs: placedIDs)
    }

    /// Adds each copy next to its original in every operation that cuts the original.
    static func addCopies(_ idMap: [UUID: UUID], toOperationsOf project: inout KerfProject) {
        for i in project.operations.indices {
            var s = project.operations[i].editableSetup
            let extra = s.shapeIDs.compactMap { idMap[$0] }
            guard !extra.isEmpty else { continue }
            s.shapeIDs += extra
            project.operations[i].editableSetup = s
        }
    }
}
