import CADCore
import Foundation
@testable import CAMCore

/// Fixtures for 3D relief tests: analytic shapes as meshes plus their exact surface depth.
enum ReliefFixture {
    /// Closed hemisphere (dome + bottom disc) of radius `r` centred at (cx, cy), z from 0 to r.
    /// Vertices lie on the sphere, so the faceted mesh is never above the analytic dome.
    static func hemisphere(radius r: Double, center c: Vec2, rings: Int = 32, segments: Int = 64) -> Mesh3D {
        var v: [Vec3] = []
        var idx: [UInt32] = []
        // Ring k at latitude k/rings * 90°, k = 0 (equator) ... rings-1; pole last.
        for k in 0..<rings {
            let lat = Double(k) / Double(rings) * .pi / 2
            for s in 0..<segments {
                let lon = Double(s) / Double(segments) * 2 * .pi
                v.append(Vec3(c.x + r * cos(lat) * cos(lon), c.y + r * cos(lat) * sin(lon), r * sin(lat)))
            }
        }
        let pole = UInt32(v.count); v.append(Vec3(c.x, c.y, r))
        let center = UInt32(v.count); v.append(Vec3(c.x, c.y, 0))
        func at(_ k: Int, _ s: Int) -> UInt32 { UInt32(k * segments + (s % segments)) }
        for k in 0..<(rings - 1) {
            for s in 0..<segments {
                idx += [at(k, s), at(k, s + 1), at(k + 1, s + 1), at(k, s), at(k + 1, s + 1), at(k + 1, s)]
            }
        }
        for s in 0..<segments { idx += [at(rings - 1, s), at(rings - 1, s + 1), pole] }
        for s in 0..<segments { idx += [center, at(0, s + 1), at(0, s)] }
        return Mesh3D(vertices: v, indices: idx)
    }

    /// Square pyramid with base `base` x `base` at (x0, y0) and apex height `h`.
    static func pyramid(base: Double, height h: Double, at o: Vec2) -> Mesh3D {
        let a = Vec3(o.x, o.y, 0), b = Vec3(o.x + base, o.y, 0), c = Vec3(o.x + base, o.y + base, 0)
        let d = Vec3(o.x, o.y + base, 0), apex = Vec3(o.x + base / 2, o.y + base / 2, h)
        return Mesh3D(vertices: [a, b, c, d, apex], indices: [0, 1, 4, 1, 2, 4, 2, 3, 4, 3, 0, 4, 0, 2, 1, 0, 3, 2])
    }

    /// A 4 x 4 x 1.25 in job with a 1 in hemisphere dome centred on it (top at the material top,
    /// bottom 1 in deep).
    static func domeDocument(zZero: ZZeroMode = .materialTop) -> (Document, PlacedModel) {
        var doc = Document(units: .inch, job: JobSetup(width: 4, height: 4, thickness: 1.25, zZero: zZero))
        let mesh = hemisphere(radius: 1, center: Vec2(0, 0))
        let model = ModelPlacement.place(mesh, name: "Dome", in: doc.job, depth: 1, zTop: 0)
        doc.models.append(model)
        return (doc, model)
    }

    /// Exact dome surface depth (below the top) for `domeDocument`.
    static func domeDepth(_ p: Vec2) -> Double {
        let r2 = (p - Vec2(2, 2)).dot(p - Vec2(2, 2))
        return r2 >= 1 ? 1 : 1 - (1 - r2).squareRoot()
    }

    /// Material-frame (xy, depth) points along every cutting move, at most `step` apart.
    static func cutSamples(_ tp: Toolpath, coords: MachineCoordinates, step: Double) -> [(Vec2, Double)] {
        var out: [(Vec2, Double)] = []
        var prev: Vec3?
        for m in tp.moves {
            guard let t = m.target else { continue }
            defer { prev = t }
            guard !m.isRapid, let p = prev else { continue }
            let a = coords.material(fromMachine: p), b = coords.material(fromMachine: t)
            let n = max(1, Int(ceil(a.xy.distance(to: b.xy) / step)))
            for k in 0...n {
                let f = Double(k) / Double(n)
                out.append((a.xy.lerp(to: b.xy, f), a.depth + (b.depth - a.depth) * f))
            }
        }
        return out
    }

    /// Largest amount the cutter dips below `surface` over all cut samples (<= 0 means no gouge).
    static func maxGouge(_ samples: [(Vec2, Double)], cutter: CutterProfile, surface: (Vec2) -> Double,
                         grid: Double = 0.01) -> Double {
        let n = Int(ceil(cutter.radius / grid))
        var worst = -Double.infinity
        for (p, d) in samples {
            for j in -n...n {
                for i in -n...n {
                    let off = Vec2(Double(i) * grid, Double(j) * grid)
                    let r = off.length
                    guard r <= cutter.radius else { continue }
                    let toolSurface = d - cutter.height(at: r)
                    worst = max(worst, toolSurface - surface(p + off))
                }
            }
        }
        return worst
    }

    /// Checks the Toolpath conventions (first rapid at safe Z, XY rapids at safe Z, end at safe Z).
    static func followsConventions(_ tp: Toolpath, coords: MachineCoordinates) -> Bool {
        guard case .rapid(let first)? = tp.moves.first, abs(first.z - coords.safeZ) < 1e-9 else { return false }
        guard let last = tp.moves.last?.target, abs(last.z - coords.safeZ) < 1e-9 else { return false }
        var prev = first
        for m in tp.moves {
            guard let t = m.target else { continue }
            if m.isRapid, !t.xy.isApproximatelyEqual(to: prev.xy, tolerance: 1e-9) {
                if t.z < coords.safeZ - 1e-9 || prev.z < coords.safeZ - 1e-9 { return false }
            }
            prev = t
        }
        return true
    }
}
