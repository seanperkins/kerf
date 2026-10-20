import Foundation

/// One solid of a 3D model (a SketchUp group / component instance, or a connected piece of an
/// STL/OBJ mesh), in document units.
public struct MeshPart: Hashable, Sendable {
    public var name: String
    public var mesh: Mesh3D

    public init(name: String, mesh: Mesh3D) { self.name = name; self.mesh = mesh }
}

/// "Import 3D Model as 2D Parts": turns the solids of a model into flat outlines to cut —
/// the usual way to make sheet-goods furniture designed in SketchUp. Each part is projected
/// along a view direction and its projected triangles are unioned into closed vectors (outer
/// outline plus any through-holes).
public enum MeshParts {
    public enum View: String, CaseIterable, Codable, Sendable {
        /// Each part lies on its largest flat face (boards come out at full face size).
        case flat
        /// Seen from above, from the front, or from the right, as assembled.
        case top, front, right
    }

    public struct Outline: Hashable, Sendable {
        public var name: String
        /// Closed loops (even-odd), in document units; for `.flat` the part's bottom-left is at
        /// the origin, other views keep model coordinates.
        public var paths: [Path]
        /// Extent of the part along the view direction (board thickness for `.flat`).
        public var thickness: Double
        public var bounds: Rect2
    }

    // MARK: Splitting

    /// Connected pieces of a mesh (triangles sharing a vertex), largest first; for STL/OBJ,
    /// which have no part structure.
    public static func connectedComponents(_ mesh: Mesh3D, name: String) -> [MeshPart] {
        var parent = Array(0..<mesh.vertices.count)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        let idx = mesh.indices.map(Int.init)
        for t in Swift.stride(from: 0, to: idx.count - 2, by: 3) {
            let a = find(idx[t]), b = find(idx[t + 1]), c = find(idx[t + 2])
            parent[b] = a
            parent[find(c)] = a
        }
        var groups: [Int: [UInt32]] = [:]
        var order: [Int] = []
        for t in Swift.stride(from: 0, to: idx.count - 2, by: 3) {
            let r = find(idx[t])
            if groups[r] == nil { order.append(r) }
            groups[r, default: []] += [mesh.indices[t], mesh.indices[t + 1], mesh.indices[t + 2]]
        }
        var parts: [Mesh3D] = order.map { r in
            // Re-index the piece's vertices.
            var map: [UInt32: UInt32] = [:]
            var verts: [Vec3] = []
            let ind: [UInt32] = groups[r]!.map { i in
                if let j = map[i] { return j }
                let j = UInt32(verts.count)
                map[i] = j
                verts.append(mesh.vertices[Int(i)])
                return j
            }
            return Mesh3D(vertices: verts, indices: ind)
        }
        parts.sort { $0.triangleCount > $1.triangleCount }
        if parts.count == 1 { return [MeshPart(name: name, mesh: parts[0])] }
        return parts.enumerated().map { MeshPart(name: "\(name) \($0.offset + 1)", mesh: $0.element) }
    }

    // MARK: Outlines

    /// The part's outline seen along `view`. Nil when nothing projects to a non-zero area.
    public static func outline(of part: MeshPart, view: View) -> Outline? {
        let rotate = rotation(for: part.mesh, view: view)
        let v = part.mesh.vertices.map(rotate)
        guard !v.isEmpty else { return nil }
        let zs = v.map(\.z)
        let thickness = (zs.max() ?? 0) - (zs.min() ?? 0)
        // Scale-aware area threshold so slivers of edge-on faces are dropped.
        let span = max(v.map(\.x).max()! - v.map(\.x).min()!, v.map(\.y).max()! - v.map(\.y).min()!, 1e-9)
        let minArea = span * span * 1e-12
        var tris: [Path] = []
        let idx = part.mesh.indices
        for t in Swift.stride(from: 0, to: idx.count - 2, by: 3) {
            var a = v[Int(idx[t])].xy, b = v[Int(idx[t + 1])].xy
            let c = v[Int(idx[t + 2])].xy
            let area = (b - a).cross(c - a) / 2
            guard abs(area) > minArea else { continue }
            if area < 0 { swap(&a, &b) }
            tris.append(Path(points: [a, b, c], closed: true))
        }
        guard !tris.isEmpty else { return nil }
        var loops = PathOps.union(tris).map { simplified($0, tolerance: span * 1e-7) }
        loops.removeAll { abs($0.signedArea()) <= minArea * 10 }
        guard !loops.isEmpty else { return nil }
        var bounds = loops.reduce(Rect2.empty) { $0.union($1.bounds()) }
        if view == .flat {
            let shift = Transform2D.translation(Vec2(-bounds.min.x, -bounds.min.y))
            loops = loops.map { $0.transformed(shift) }
            bounds = loops.reduce(Rect2.empty) { $0.union($1.bounds()) }
        }
        return Outline(name: part.name, paths: loops, thickness: thickness, bounds: bounds)
    }

    /// Maps model coordinates so that the view direction becomes −Z (looking down).
    static func rotation(for mesh: Mesh3D, view: View) -> (Vec3) -> Vec3 {
        switch view {
        case .top: return { $0 }
        case .front: return { Vec3($0.x, $0.z, -$0.y) }   // looking along +Y
        case .right: return { Vec3($0.y, $0.z, $0.x) }    // looking along −X
        case .flat:
            let n = dominantNormal(mesh)
            return { rotate($0, bringing: n) }
        }
    }

    /// The face direction with the most area (n and −n count together), sign-normalised.
    static func dominantNormal(_ mesh: Mesh3D) -> Vec3 {
        struct Key: Hashable { var x: Int, y: Int, z: Int }
        var area: [Key: (Double, Vec3)] = [:]
        let idx = mesh.indices
        for t in Swift.stride(from: 0, to: idx.count - 2, by: 3) {
            let a = mesh.vertices[Int(idx[t])], b = mesh.vertices[Int(idx[t + 1])], c = mesh.vertices[Int(idx[t + 2])]
            let cr = (b - a).cross(c - a)
            let len = cr.length
            guard len > 0 else { continue }
            var n = cr / len
            if n.x < -1e-9 || (abs(n.x) <= 1e-9 && (n.y < -1e-9 || (abs(n.y) <= 1e-9 && n.z < 0))) { n = n * -1 }
            let k = Key(x: Int((n.x * 200).rounded()), y: Int((n.y * 200).rounded()), z: Int((n.z * 200).rounded()))
            let prev = area[k] ?? (0, .zero)
            area[k] = (prev.0 + len / 2, prev.1 + n * (len / 2))
        }
        // Prefer the vertical direction on ties so already-flat parts stay as drawn.
        let best = area.values.max { l, r in
            abs(l.0 - r.0) > 1e-9 * max(l.0, r.0) ? l.0 < r.0 : abs(l.1.normalized.z) < abs(r.1.normalized.z)
        }
        let n = best?.1.normalized ?? Vec3(0, 0, 1)
        return n.length > 0 ? n : Vec3(0, 0, 1)
    }

    /// Rotates `p` by the rotation taking unit vector `n` to +Z (or −Z to +Z by flipping Y).
    static func rotate(_ p: Vec3, bringing n: Vec3) -> Vec3 {
        let z = Vec3(0, 0, 1)
        let c = n.dot(z)
        if c > 1 - 1e-12 { return p }
        if c < -1 + 1e-12 { return Vec3(p.x, -p.y, -p.z) }
        let axis = n.cross(z).normalized
        let s = (1 - c * c).squareRoot()
        // Rodrigues: p cosθ + (k×p) sinθ + k (k·p)(1−cosθ)
        return p * c + axis.cross(p) * s + axis * (axis.dot(p) * (1 - c))
    }

    /// Drops points that lie on the straight line between their neighbours (T-junction
    /// vertices left by unioning triangles).
    static func simplified(_ path: Path, tolerance: Double) -> Path {
        var pts = path.flattened()
        if pts.count > 1, pts.first!.isApproximatelyEqual(to: pts.last!, tolerance: tolerance) { pts.removeLast() }
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            var i = 0
            while i < pts.count && pts.count > 3 {
                let a = pts[(i + pts.count - 1) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
                let ac = c - a
                let len = ac.length
                let dev = len > 0 ? abs(ac.cross(b - a)) / len : (b - a).length
                if dev <= tolerance && (b - a).dot(ac) >= -tolerance && (b - c).dot(a - c) >= -tolerance {
                    pts.remove(at: i)
                    changed = true
                } else {
                    i += 1
                }
            }
        }
        return Path(points: pts, closed: true)
    }

    // MARK: Layout

    /// Shelf layout of `.flat` outlines from `origin`, left to right, rows wrapping at
    /// `rowWidth`, `gap` apart. Returns each outline's offset. Parts wider than the row get a
    /// row of their own.
    public static func shelfOffsets(_ sizes: [Vec2], origin: Vec2, rowWidth: Double, gap: Double) -> [Vec2] {
        var out: [Vec2] = []
        var x = origin.x, y = origin.y, rowHeight = 0.0
        for s in sizes {
            if x > origin.x && x + s.x > origin.x + rowWidth + 1e-9 {
                x = origin.x
                y += rowHeight + gap
                rowHeight = 0
            }
            out.append(Vec2(x, y))
            x += s.x + gap
            rowHeight = max(rowHeight, s.y)
        }
        return out
    }

    /// Outlines of every part, placed: `.flat` parts on shelves inside `area` (from its bottom
    /// left, wrapping at its width), other views keep their assembled positions and the whole
    /// set is centred on `area`. Parts that project to nothing are skipped.
    public static func layout(_ parts: [MeshPart], view: View, area: Rect2, gap: Double) -> [Outline] {
        var outlines = parts.compactMap { outline(of: $0, view: view) }
        guard !outlines.isEmpty else { return [] }
        if view == .flat {
            let offsets = shelfOffsets(outlines.map { Vec2($0.bounds.width, $0.bounds.height) },
                                       origin: Vec2(area.min.x + gap, area.min.y + gap),
                                       rowWidth: max(area.width - 2 * gap, 0), gap: gap)
            for i in outlines.indices { outlines[i] = moved(outlines[i], by: offsets[i]) }
        } else {
            let all = outlines.reduce(Rect2.empty) { $0.union($1.bounds) }
            let d = area.center - all.center
            for i in outlines.indices { outlines[i] = moved(outlines[i], by: d) }
        }
        return outlines
    }

    static func moved(_ o: Outline, by d: Vec2) -> Outline {
        var o = o
        let t = Transform2D.translation(d)
        o.paths = o.paths.map { $0.transformed(t) }
        o.bounds = o.paths.reduce(Rect2.empty) { $0.union($1.bounds()) }
        return o
    }
}
