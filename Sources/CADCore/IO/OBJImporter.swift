import Foundation

/// Wavefront OBJ mesh import (geometry only: `v` and `f`; texture/normal indices, groups,
/// materials and free-form surfaces are ignored). Polygons are fan-triangulated; negative
/// (relative) indices are supported.
///
/// OBJ has no units or fixed up axis. Like STL, coordinates are assumed to be millimetres.
/// Most modelling tools write OBJ with Y up, so by default (`yUp`) the model is rotated so
/// its Y axis becomes Kerf's Z (the top of the relief): (x, y, z) → (x, −z, y).
public struct OBJImporter: MeshImporter {
    public static let fileExtensions = ["obj"]
    public var sourceUnits: LengthUnit
    public var yUp: Bool

    public init(sourceUnits: LengthUnit = .millimeter, yUp: Bool = true) {
        self.sourceUnits = sourceUnits; self.yUp = yUp
    }

    public func importMesh(from data: Data, targetUnits: LengthUnit) throws -> Mesh3D {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw KerfIOError.malformed("OBJ: unreadable text")
        }
        var verts: [Vec3] = []
        var tris: [(Vec3, Vec3, Vec3)] = []
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("v ") || line.hasPrefix("v\t") {
                let n = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).prefix(3).compactMap { Double($0) }
                guard n.count == 3, n.allSatisfy(\.isFinite) else { throw KerfIOError.malformed("OBJ: bad vertex '\(line)'") }
                verts.append(yUp ? Vec3(n[0], -n[2], n[1]) : Vec3(n[0], n[1], n[2]))
            } else if line.hasPrefix("f ") || line.hasPrefix("f\t") {
                var idx: [Int] = []
                for tok in line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                    guard let first = tok.split(separator: "/", omittingEmptySubsequences: false).first,
                          let i = Int(first), i != 0 else { throw KerfIOError.malformed("OBJ: bad face '\(line)'") }
                    let k = i > 0 ? i - 1 : verts.count + i
                    guard k >= 0, k < verts.count else { throw KerfIOError.malformed("OBJ: face index out of range") }
                    idx.append(k)
                }
                guard idx.count >= 3 else { continue }
                for j in 1..<(idx.count - 1) { tris.append((verts[idx[0]], verts[idx[j]], verts[idx[j + 1]])) }
            }
        }
        guard !tris.isEmpty else { throw KerfIOError.malformed("OBJ contains no faces") }
        return STLImporter.indexed(tris, scale: sourceUnits.factor(to: targetUnits))
    }
}
