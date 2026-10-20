import CADCore
import Foundation
import Testing
@testable import CAMCore

/// Shared fixtures for the V-carve / inlay tests.
enum VCarveFixture {
    static let vbit60 = ToolLibrary.seeded.tools[5]      // 60° V-bit, 1/2" dia
    static let endMill = ToolLibrary.seeded.tools[0]     // 1/4" end mill
    static let tan30 = tan(30.0 * .pi / 180)

    static func context(_ paths: [Path], zZero: ZZeroMode = .materialTop, origin: XYOrigin = .lowerLeft,
                        units: LengthUnit = .inch) -> (CAMContext, OperationSetup) {
        var doc = Document(units: units)
        doc.job.zZero = zZero
        doc.job.xyOrigin = origin
        let shape = Shape(layerID: doc.defaultLayerID, paths: paths)
        doc.add(shape)
        let setup = OperationSetup(name: "V", toolID: vbit60.id, shapeIDs: [shape.id])
        return (CAMContext(document: doc, tools: .seeded), setup)
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        Path(points: [Vec2(x, y), Vec2(x + w, y), Vec2(x + w, y + h), Vec2(x, y + h)], closed: true)
    }

    static func circle(_ c: Vec2, _ r: Double, clockwise: Bool = false) -> Path {
        let n = 96
        var pts = (0..<n).map { i -> Vec2 in
            let a = Double(i) / Double(n) * 2 * .pi
            return Vec2(c.x + r * cos(a), c.y + r * sin(a))
        }
        if clockwise { pts.reverse() }
        return Path(points: pts, closed: true)
    }

    /// Material-frame cut points (xy, depth) of all feed moves, densified to `step`.
    static func cutPoints(_ tp: Toolpath, coords: MachineCoordinates, step: Double = 0.005) -> [(xy: Vec2, depth: Double)] {
        var out: [(Vec2, Double)] = []
        var last: Vec3?
        for m in tp.moves {
            guard let t = m.target else { continue }
            defer { last = t }
            guard !m.isRapid, let a = last else { continue }
            let n = max(1, Int((a.xy.distance(to: t.xy) / step).rounded(.up)))
            for k in 1...n {
                let p = a + (t - a) * (Double(k) / Double(n))
                let mat = coords.material(fromMachine: p)
                out.append((mat.xy, mat.depth))
            }
        }
        return out
    }

    /// Depth of material removed at `q` by a sharp V-bit (half-angle slope) following `pts`.
    static func removedDepth(at q: Vec2, by pts: [(xy: Vec2, depth: Double)], slope: Double) -> Double {
        pts.reduce(0) { max($0, $1.depth - $1.xy.distance(to: q) / slope) }
    }

    /// The toolpath safety conventions every generator must follow.
    static func expectSafeMotion(_ tp: Toolpath, coords: MachineCoordinates) {
        guard case .rapid(let first)? = tp.moves.first else { Issue.record("first move is not a rapid"); return }
        #expect(abs(first.z - coords.safeZ) < 1e-9)
        #expect(abs((tp.moves.last?.target?.z ?? 0) - coords.safeZ) < 1e-9)
        var prev = first
        for m in tp.moves.dropFirst() {
            guard let t = m.target else { continue }
            if m.isRapid, t.xy.distance(to: prev.xy) > 1e-9 {
                #expect(t.z >= coords.safeZ - 1e-9 && prev.z >= coords.safeZ - 1e-9, "XY rapid below safe Z")
            }
            prev = t
        }
    }
}
