import Foundation

/// STL (binary + ASCII) import. Owned by the cam-3d workstream.
///
/// STL files carry no units; they are assumed to be in millimetres (the de-facto convention of
/// modelling tools and slicers) and converted to `targetUnits`. Coincident vertices are merged
/// so the result is an indexed mesh; degenerate (zero-area) triangles are dropped.
public struct STLImporter: MeshImporter {
    public static let fileExtensions = ["stl"]
    /// Units STL coordinates are assumed to be in.
    public var sourceUnits: LengthUnit

    public init(sourceUnits: LengthUnit = .millimeter) { self.sourceUnits = sourceUnits }

    public func importMesh(from data: Data, targetUnits: LengthUnit) throws -> Mesh3D {
        let triangles: [(Vec3, Vec3, Vec3)]
        if Self.looksBinary(data) {
            triangles = try Self.parseBinary(data)
        } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("solid") {
            triangles = try Self.parseASCII(text)
        } else {
            throw KerfIOError.malformed("Not a binary or ASCII STL file")
        }
        guard !triangles.isEmpty else { throw KerfIOError.malformed("STL contains no triangles") }
        let f = sourceUnits.factor(to: targetUnits)
        return Self.indexed(triangles, scale: f)
    }

    // MARK: Parsing

    /// Binary STL: 80-byte header, UInt32 count, then 50 bytes per triangle. A file whose size
    /// matches that layout exactly is binary even if the header starts with "solid".
    static func looksBinary(_ data: Data) -> Bool {
        guard data.count >= 84 else { return false }
        let n = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian }
        return 84 + Int(n) * 50 == data.count
    }

    static func parseBinary(_ data: Data) throws -> [(Vec3, Vec3, Vec3)] {
        try data.withUnsafeBytes { raw -> [(Vec3, Vec3, Vec3)] in
            let n = Int(raw.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian)
            guard 84 + n * 50 <= raw.count else { throw KerfIOError.malformed("Truncated binary STL") }
            func vertex(_ off: Int) -> Vec3 {
                func f(_ o: Int) -> Double {
                    Double(Float(bitPattern: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian))
                }
                return Vec3(f(off), f(off + 4), f(off + 8))
            }
            var tris: [(Vec3, Vec3, Vec3)] = []
            tris.reserveCapacity(n)
            for i in 0..<n {
                let base = 84 + i * 50 + 12 // skip the facet normal
                let tri = (vertex(base), vertex(base + 12), vertex(base + 24))
                guard tri.0.isFinite, tri.1.isFinite, tri.2.isFinite else {
                    throw KerfIOError.malformed("Binary STL: triangle \(i + 1) has a non-finite vertex")
                }
                tris.append(tri)
            }
            return tris
        }
    }

    static func parseASCII(_ text: String) throws -> [(Vec3, Vec3, Vec3)] {
        var tris: [(Vec3, Vec3, Vec3)] = []
        var pending: [Vec3] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let head = parts.first?.lowercased() else { continue }
            switch head {
            case "vertex":
                guard parts.count >= 4, let x = Double(parts[1]), let y = Double(parts[2]), let z = Double(parts[3]),
                      x.isFinite, y.isFinite, z.isFinite
                else { throw KerfIOError.malformed("Bad vertex line: \(line)") }
                pending.append(Vec3(x, y, z))
            case "endloop":
                // Polygons with more than 3 vertices (rare, non-standard) are fanned.
                if pending.count >= 3 {
                    for k in 1..<(pending.count - 1) { tris.append((pending[0], pending[k], pending[k + 1])) }
                }
                pending.removeAll(keepingCapacity: true)
            default:
                continue
            }
        }
        return tris
    }

    // MARK: Indexing

    /// Merges vertices that coincide after scaling (quantised to 1e-9 relative grid) and drops
    /// degenerate triangles.
    static func indexed(_ tris: [(Vec3, Vec3, Vec3)], scale f: Double) -> Mesh3D {
        struct Key: Hashable { var x: Int64, y: Int64, z: Int64 }
        let q = 1e7 // quantisation: 1e-7 of a unit after scaling
        var lookup: [Key: UInt32] = [:]
        var vertices: [Vec3] = []
        var indices: [UInt32] = []
        indices.reserveCapacity(tris.count * 3)
        // Clamped so a huge coordinate cannot trap the Int64 conversion.
        func cell(_ v: Double) -> Int64 {
            let r = (v * q).rounded()
            return r.isFinite ? Int64(max(-9e18, min(9e18, r))) : 0
        }
        func index(_ v: Vec3) -> UInt32 {
            let s = Vec3(v.x * f, v.y * f, v.z * f)
            let k = Key(x: cell(s.x), y: cell(s.y), z: cell(s.z))
            if let i = lookup[k] { return i }
            let i = UInt32(vertices.count)
            vertices.append(s)
            lookup[k] = i
            return i
        }
        for (a, b, c) in tris {
            let ia = index(a), ib = index(b), ic = index(c)
            if ia == ib || ib == ic || ia == ic { continue }
            indices += [ia, ib, ic]
        }
        return Mesh3D(vertices: vertices, indices: indices)
    }
}
