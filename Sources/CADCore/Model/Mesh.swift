import Foundation

/// Indexed triangle mesh (from STL import) in document units.
public struct Mesh3D: Codable, Hashable, Sendable {
    public var vertices: [Vec3]
    /// Triangle vertex indices, 3 per triangle, counter-clockwise = outward.
    public var indices: [UInt32]

    public init(vertices: [Vec3] = [], indices: [UInt32] = []) {
        self.vertices = vertices; self.indices = indices
    }

    public var triangleCount: Int { indices.count / 3 }

    public var bounds: (min: Vec3, max: Vec3)? {
        guard let f = vertices.first else { return nil }
        var lo = f, hi = f
        for v in vertices {
            lo = Vec3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
            hi = Vec3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
        }
        return (lo, hi)
    }
}

/// A 3D model placed on the material for 3D (Relief3D) toolpaths.
public struct PlacedModel: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var mesh: Mesh3D
    /// Model XY placement: mesh XY is scaled by `scale` then translated by `offset` (material frame).
    public var offset: Vec2
    public var scale: Double
    /// Depth below material top of the model's lowest point (model top sits at material top - zTop).
    public var depth: Double
    public var zTop: Double

    public init(id: UUID = UUID(), name: String, mesh: Mesh3D, offset: Vec2 = .zero,
                scale: Double = 1, depth: Double = 0.5, zTop: Double = 0) {
        self.id = id; self.name = name; self.mesh = mesh; self.offset = offset; self.scale = scale
        self.depth = depth; self.zTop = zTop
    }
}
