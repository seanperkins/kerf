import CADCore
import Foundation
import Testing
@testable import CAMCore

/// Shared fixtures and invariant checks for the Ops2D tests.
enum Ops2DFixture {
    static let endMill = ToolLibrary.seeded.tools[0]   // 1/4" end mill, stepdown 0.125, stepover 0.1
    static let smallEndMill = ToolLibrary.seeded.tools[1] // 1/8"
    static let bigEndMill = ToolLibrary.seeded.tools[2]   // 1/2"
    static let drill = ToolLibrary.seeded.tools[8]

    static func document(_ paths: [Path], zZero: ZZeroMode = .materialTop, origin: XYOrigin = .lowerLeft,
                         units: LengthUnit = .inch) -> (CAMContext, [UUID]) {
        var doc = Document(units: units)
        doc.job.zZero = zZero
        doc.job.xyOrigin = origin
        var ids: [UUID] = []
        for p in paths {
            let s = Shape(layerID: doc.defaultLayerID, paths: [p])
            doc.add(s)
            ids.append(s.id)
        }
        return (CAMContext(document: doc, tools: .seeded), ids)
    }

    /// Single shape holding several paths (e.g. a ring = outer + hole).
    static func document(shapePaths: [Path], zZero: ZZeroMode = .materialTop) -> (CAMContext, [UUID]) {
        var doc = Document()
        doc.job.zZero = zZero
        let s = Shape(layerID: doc.defaultLayerID, paths: shapePaths)
        doc.add(s)
        return (CAMContext(document: doc, tools: .seeded), [s.id])
    }

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
        ShapeFactory.rectangle(Rect2(x: x, y: y, width: w, height: h))
    }

    /// Every move's end point plus interior samples of arcs, in machine coordinates.
    static func densePoints(_ moves: [Move], includeRapids: Bool = false) -> [Vec3] {
        var out: [Vec3] = []
        var cur: Vec3?
        for m in moves {
            switch m {
            case .rapid(let p):
                if includeRapids { out.append(p) }
                cur = p
            case .linear(let p, _):
                out.append(p); cur = p
            case .arcCW(let p, let c, _), .arcCCW(let p, let c, _):
                if let s = cur {
                    let cw: Bool = { if case .arcCW = m { return true } else { return false } }()
                    let sweep = Flattening.arcSweep(from: s.xy, to: p.xy, center: c, clockwise: cw)
                    let r = s.xy.distance(to: c)
                    let a0 = (s.xy - c).angle
                    for k in 1...16 {
                        let t = Double(k) / 16
                        let a = a0 + (cw ? -1 : 1) * abs(sweep) * t
                        out.append(Vec3(c + Vec2(cos(a), sin(a)) * r, z: s.z + (p.z - s.z) * t))
                    }
                }
                cur = p
            case .dwell: break
            }
        }
        return out
    }

    /// Checks the Toolpath conventions; returns failure descriptions.
    static func conventionViolations(_ tp: Toolpath, coords: MachineCoordinates) -> [String] {
        var issues: [String] = []
        let safe = coords.safeZ
        guard let first = tp.moves.first else { return ["no moves"] }
        if case .rapid(let p) = first, abs(p.z - safe) < 1e-9 {} else { issues.append("first move not rapid at safe Z") }
        var cur: Vec3?
        for (i, m) in tp.moves.enumerated() {
            if case .rapid(let p) = m, let c = cur, c.xy.distance(to: p.xy) > 1e-9 {
                if p.z < safe - 1e-9 || c.z < safe - 1e-9 { issues.append("XY rapid below safe Z at move \(i)") }
            }
            if let t = m.target { cur = t }
            if let f = m.feed, f <= 0 { issues.append("non-positive feed at \(i)") }
        }
        if let c = cur, abs(c.z - safe) > 1e-9 { issues.append("does not end at safe Z") }
        return issues
    }

    /// Distance from q to the boundary of an axis-aligned rectangle.
    static func distanceToRectBoundary(_ q: Vec2, _ r: Rect2) -> Double {
        let corners = [r.min, Vec2(r.max.x, r.min.y), r.max, Vec2(r.min.x, r.max.y)]
        return Polygon2D.distance(from: q, toLoop: corners)
    }
}
