import CADCore
import Foundation

/// Checks toolpaths against keep-out zones: the tool (its radius plus `margin`) must not come
/// over a zone while lower than the zone's top plus `margin`. Rapids are checked too.
public enum KeepOut {
    public struct Violation: Hashable, Sendable {
        public var toolpathName: String
        public var zoneName: String
        public var isRapid: Bool
        /// Where it happens (material frame).
        public var at: Vec2
    }

    public static func violations(_ toolpaths: [Toolpath], zones: [KeepOutZone], coords: MachineCoordinates,
                                  margin: Double, tolerance: Double) -> [Violation] {
        let usable = zones.filter { $0.outline.count > 2 }
        guard !usable.isEmpty else { return [] }
        var out: [Violation] = []
        for tp in toolpaths {
            let r = tp.tool.radius + max(margin, 0)
            // Zone outlines grown by the tool radius + margin, as machine-frame regions.
            let grown: [(zone: KeepOutZone, region: [[Vec2]], topZ: Double, box: Rect2)] = usable.map { z in
                let region = GeomKernel.offset([Polygon2D.signedArea(z.outline) < 0 ? z.outline.reversed() : z.outline],
                                               by: r, join: .round, arcTolerance: tolerance)
                    .map { $0.map { coords.machineXY($0) } }
                let topZ = coords.z(depth: -(z.height + max(margin, 0)))
                return (z, region, topZ, Rect2(points: region.flatMap { $0 }))
            }
            var reported = Set<UUID>()
            var cur: Vec3?
            // Any segment that crosses a zone crosses its grown outline for at least 2r: sampling
            // every 0.9r cannot step over it.
            let step = max(r * 0.9, tolerance * 10)
            for m in tp.moves {
                guard let target = m.target else { continue }
                defer { cur = target }
                guard let from = cur else { continue }
                let pts = samples(from: from, move: m, step: step)
                for g in grown where !reported.contains(g.zone.id) {
                    for p in pts where p.z < g.topZ - 1e-9 && g.box.contains(p.xy) && Polygon2D.regionContains(g.region, p.xy) {
                        reported.insert(g.zone.id)
                        out.append(Violation(toolpathName: tp.name, zoneName: g.zone.name, isRapid: m.isRapid,
                                             at: coords.materialXY(fromMachine: p.xy)))
                        break
                    }
                }
            }
        }
        return out
    }

    /// Points along a move (arcs sampled around their centre), including both ends.
    static func samples(from a: Vec3, move m: Move, step: Double) -> [Vec3] {
        guard let b = m.target else { return [] }
        switch m {
        case .arcCW(_, let c, _), .arcCCW(_, let c, _):
            let cw: Bool = { if case .arcCW = m { return true } else { return false } }()
            let sweep = Flattening.arcSweep(from: a.xy, to: b.xy, center: c, clockwise: cw)
            let radius = a.xy.distance(to: c)
            let n = max(2, Int((abs(sweep) * radius / step).rounded(.up)))
            let a0 = (a.xy - c).angle
            return (0...n).map { k in
                let t = Double(k) / Double(n)
                let ang = a0 + (cw ? -1 : 1) * abs(sweep) * t
                return Vec3(c + Vec2(cos(ang), sin(ang)) * radius, z: a.z + (b.z - a.z) * t)
            }
        default:
            let n = max(1, Int((a.xy.distance(to: b.xy) / step).rounded(.up)))
            return (0...n).map { k in
                let t = Double(k) / Double(n)
                return Vec3(a.xy.lerp(to: b.xy, t), z: a.z + (b.z - a.z) * t)
            }
        }
    }
}
