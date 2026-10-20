import CADCore
import Foundation

/// Maps a `PlacedModel`'s mesh into the material frame:
///  * XY: `mesh.xy * scale + offset`;
///  * Z: the mesh's highest point sits `zTop` below the material top and its lowest point
///    `depth` below it (Z is stretched/squashed independently of XY to fit that range).
public extension PlacedModel {
    /// Material-frame XY of a mesh vertex.
    func materialXY(_ v: Vec3) -> Vec2 { Vec2(v.x * scale + offset.x, v.y * scale + offset.y) }

    /// XY footprint of the placed model in the material frame (empty for an empty mesh).
    var footprint: Rect2 {
        guard let b = mesh.bounds else { return .empty }
        return Rect2(points: [materialXY(b.min), materialXY(b.max)])
    }

    /// Converts mesh Z to depth below the material top. Returns a closure so the mesh bounds are
    /// computed once.
    func depthMapper() -> (Double) -> Double {
        guard let b = mesh.bounds else { return { _ in depth } }
        let span = b.max.z - b.min.z
        let top = zTop, bottom = depth
        guard span > 1e-12 else { return { _ in top } }
        let k = (bottom - top) / span
        let zMax = b.max.z
        return { z in top + (zMax - z) * k }
    }
}

/// Helpers to place an imported mesh onto the material (the "Import 3D model" dialog).
public enum ModelPlacement {
    public enum Anchor: Sendable { case center, lowerLeft }

    /// Places `mesh` so its XY footprint fits `targetSize` (aspect preserved; pass nil to keep
    /// the mesh's own size) anchored on the material, with its top `zTop` below the material
    /// top and its bottom `depth` below it.
    public static func place(_ mesh: Mesh3D, name: String, in job: JobSetup, fitting targetSize: Vec2? = nil,
                             depth: Double, zTop: Double = 0, anchor: Anchor = .center) -> PlacedModel {
        guard let b = mesh.bounds else { return PlacedModel(name: name, mesh: mesh, depth: depth, zTop: zTop) }
        let w = b.max.x - b.min.x, h = b.max.y - b.min.y
        var scale = 1.0
        if let t = targetSize {
            let sx = w > 1e-12 ? t.x / w : .infinity, sy = h > 1e-12 ? t.y / h : .infinity
            let s = min(sx, sy)
            if s.isFinite, s > 0 { scale = s }
        }
        let size = Vec2(w * scale, h * scale)
        let targetMin: Vec2
        switch anchor {
        case .center: targetMin = Vec2((job.width - size.x) / 2, (job.height - size.y) / 2)
        case .lowerLeft: targetMin = .zero
        }
        let offset = targetMin - Vec2(b.min.x * scale, b.min.y * scale)
        return PlacedModel(name: name, mesh: mesh, offset: offset, scale: scale, depth: depth, zTop: zTop)
    }
}
