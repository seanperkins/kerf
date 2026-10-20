import CADCore
import CAMCore
import Foundation
import UniformTypeIdentifiers

struct ImportOutcome: Equatable {
    var shapeIDs: [UUID] = []
    var modelIDs: [UUID] = []
    var warnings: [String] = []
}

/// File > Import: vectors (SVG/DXF/EPS) become shapes on their own layers; STL becomes a
/// placed 3D model centred on the material.
enum ImportService {
    static let vectorExtensions = ["svg", "dxf", "eps"]
    static let meshExtensions = ["stl"]
    static var allExtensions: [String] { vectorExtensions + meshExtensions }

    static var allowedContentTypes: [UTType] {
        allExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func importFile(data: Data, fileName: String, into project: inout KerfProject) throws -> ImportOutcome {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let base = (fileName as NSString).deletingPathExtension
        let units = project.document.units
        if meshExtensions.contains(ext) {
            let mesh = try STLImporter().importMesh(from: data, targetUnits: units)
            let model = place(mesh: mesh, name: base, job: project.document.job)
            project.document.models.append(model)
            return ImportOutcome(modelIDs: [model.id])
        }
        guard let importer = FileFormats.importer(forExtension: ext) else {
            throw KerfIOError.unsupportedFormat(ext)
        }
        let result = try importer.importVectors(from: data, targetUnits: units)
        var outcome = ImportOutcome(warnings: result.warnings)
        // Keep importer layers; fall back to a layer named after the file.
        var layerMap: [UUID: UUID] = [:]
        for l in result.layers {
            if let existing = project.document.layers.first(where: { $0.name == l.name }) {
                layerMap[l.id] = existing.id
            } else {
                project.document.layers.append(l)
                layerMap[l.id] = l.id
            }
        }
        var fallback: UUID?
        for var s in result.shapes {
            if let mapped = layerMap[s.layerID] {
                s.layerID = mapped
            } else {
                if fallback == nil { fallback = project.addLayer(named: base) }
                s.layerID = fallback!
            }
            if s.name.isEmpty { s.name = base }
            project.document.add(s)
            outcome.shapeIDs.append(s.id)
        }
        if outcome.shapeIDs.isEmpty { outcome.warnings.append("The file contained no supported vectors.") }
        return outcome
    }

    /// Centres the mesh on the material, model top flush with the material top, and depth equal
    /// to the mesh's Z extent (clamped to the material thickness).
    static func place(mesh: Mesh3D, name: String, job: JobSetup) -> PlacedModel {
        guard let b = mesh.bounds else { return PlacedModel(name: name, mesh: mesh) }
        let size = Vec2(b.max.x - b.min.x, b.max.y - b.min.y)
        let center = Vec2(b.min.x, b.min.y) + size * 0.5
        let offset = job.materialBounds.center - center
        let depth = min(max(b.max.z - b.min.z, 0), job.thickness)
        return PlacedModel(name: name.isEmpty ? "Model" : name, mesh: mesh, offset: offset, scale: 1,
                           depth: depth > 0 ? depth : job.thickness / 2, zTop: 0)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case KerfIOError.notImplemented(let what): return "\(what) is not available in this build yet."
        case KerfIOError.unsupportedFormat(let ext): return "Kerf cannot import .\(ext) files."
        case KerfIOError.malformed(let msg): return "The file could not be read: \(msg)"
        default: return error.localizedDescription
        }
    }
}
