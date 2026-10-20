import Foundation

/// Placement of copies along a guide vector.
public enum CopyAlong {
    /// Transforms moving an object centred at `objectCenter` to `count` evenly spaced points
    /// along `guide` (ends included on open guides; closed guides do not repeat the start).
    /// With `rotate`, each copy turns to the guide's direction (the original's orientation
    /// counts as pointing along +X).
    public static func transforms(along guide: Path, count: Int, objectCenter: Vec2, rotate: Bool,
                                  tolerance: Double = Path.defaultTolerance) -> [Transform2D] {
        guard count >= 1, !guide.isEmpty else { return [] }
        let w = TextOnPath.Walker(guide, tolerance: tolerance)
        guard w.length > 0 else { return [] }
        let step = count == 1 ? 0 : w.length / Double(guide.isClosed ? count : count - 1)
        return (0..<count).map { i in
            let (p, tangent) = w.pointAndTangent(at: count == 1 ? w.length / 2 : step * Double(i))
            var t = Transform2D.translation(-objectCenter)
            if rotate { t = t.concatenating(.rotation(atan2(tangent.y, tangent.x))) }
            return t.concatenating(.translation(p))
        }
    }

    /// Number of copies that fit when spaced `spacing` apart along `guide`.
    public static func count(along guide: Path, spacing: Double, tolerance: Double = Path.defaultTolerance) -> Int {
        guard spacing > 0 else { return 0 }
        let l = TextOnPath.Walker(guide, tolerance: tolerance).length
        return guide.isClosed ? max(1, Int((l / spacing).rounded(.down))) : Int((l / spacing).rounded(.down)) + 1
    }
}
