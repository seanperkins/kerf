import CADCore
import CAMCore
import Foundation

extension Move {
    /// The same move with every length and feed multiplied by `f` (unit conversion).
    func scaled(by f: Double) -> Move {
        guard f != 1 else { return self }
        func s(_ p: Vec3) -> Vec3 { Vec3(p.x * f, p.y * f, p.z * f) }
        switch self {
        case .rapid(let p): return .rapid(to: s(p))
        case .linear(let p, let feed): return .linear(to: s(p), feed: feed * f)
        case .arcCW(let p, let c, let feed): return .arcCW(to: s(p), center: c * f, feed: feed * f)
        case .arcCCW(let p, let c, let feed): return .arcCCW(to: s(p), center: c * f, feed: feed * f)
        case .dwell: return self
        }
    }
}

extension Toolpath {
    /// Moves and tool converted from `from` units by factor `f` (tool converted to `to`).
    func scaled(from: LengthUnit, to: LengthUnit) -> Toolpath {
        guard from != to else { return self }
        let f = from.factor(to: to)
        var tp = self
        tp.moves = moves.map { $0.scaled(by: f) }
        tp.tool = tool.converted(to: to)
        return tp
    }
}
