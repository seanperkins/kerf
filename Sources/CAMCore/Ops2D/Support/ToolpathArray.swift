import CADCore
import Foundation

extension Move {
    /// The same move shifted by `d` in XY (machine and material frames differ only by a shift,
    /// so a material-frame offset is the same in both).
    public func translated(by d: Vec2) -> Move {
        func t(_ p: Vec3) -> Vec3 { Vec3(p.xy + d, z: p.z) }
        switch self {
        case .rapid(let p): return .rapid(to: t(p))
        case .linear(let p, let f): return .linear(to: t(p), feed: f)
        case .arcCW(let p, let c, let f): return .arcCW(to: t(p), center: c + d, feed: f)
        case .arcCCW(let p, let c, let f): return .arcCCW(to: t(p), center: c + d, feed: f)
        case .dwell: return self
        }
    }
}

public enum ToolpathArray {
    /// Each toolpath repeated at every offset of `settings`, all copies in one toolpath. Every
    /// copy starts and ends at safe Z, so the rapids between copies stay at safe Z.
    /// With `coords`, a copy whose cuts leave the material gets a warning.
    public static func apply(_ settings: ArrayCopySettings, to toolpaths: [Toolpath], coords: MachineCoordinates? = nil,
                             tolerance: Double = 1e-6) -> [Toolpath] {
        guard settings.count > 1 else { return toolpaths }
        let offsets = settings.offsets
        return toolpaths.map { tp in
            var out = tp
            out.moves = offsets.flatMap { d in d == .zero ? tp.moves : tp.moves.map { $0.translated(by: d) } }
            out.metadata["copies"] = "\(offsets.count) (\(max(settings.columns, 1)) × \(max(settings.rows, 1)))"
            if let coords {
                let cuts = out.moves.filter { !$0.isRapid }.compactMap { $0.target?.xy }.map { coords.materialXY(fromMachine: $0) }
                let b = Rect2(points: cuts)
                let m = coords.job.materialBounds.insetBy(-tolerance)
                if !cuts.isEmpty, !(m.contains(b.min) && m.contains(b.max)) {
                    let w = "array copies run off the material"
                    out.metadata["warning"] = out.metadata["warning"].map { "\($0); \(w)" } ?? w
                }
            }
            return out
        }
    }
}
