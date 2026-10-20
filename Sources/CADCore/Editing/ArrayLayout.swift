import Foundation

/// Placement of array copies (rectangular grid, circular). Results exclude the original.
public enum ArrayLayout {
    public enum Spacing: String, Codable, CaseIterable, Sendable {
        /// Distance between matching points of neighbouring copies (centre to centre).
        case offset
        /// Clear gap between the bounding boxes of neighbouring copies.
        case gap
    }

    /// Translations for a `rows` × `columns` grid. Columns run in +X, rows in +Y (negative
    /// values go the other way). `size` is the selection's bounding-box size, used for `.gap`.
    public static func rectangular(rows: Int, columns: Int, x: Double, y: Double, spacing: Spacing,
                                   size: Vec2) -> [Vec2] {
        guard rows >= 1, columns >= 1 else { return [] }
        let dx = spacing == .gap ? size.x + x : x
        let dy = spacing == .gap ? size.y + y : y
        var out: [Vec2] = []
        for r in 0..<rows {
            for c in 0..<columns where r != 0 || c != 0 {
                out.append(Vec2(Double(c) * dx, Double(r) * dy))
            }
        }
        return out
    }

    /// Transforms for `count` total items (original included) around `center`, `step` degrees
    /// apart (counter-clockwise when positive). When `rotateCopies` is false copies keep their
    /// orientation and are only moved around the circle.
    public static func circular(count: Int, center: Vec2, stepDegrees: Double, rotateCopies: Bool,
                                selectionCenter: Vec2) -> [Transform2D] {
        guard count >= 2 else { return [] }
        return (1..<count).map { i in
            let a = stepDegrees * Double(i) * .pi / 180
            if rotateCopies { return .rotation(a, about: center) }
            let moved = (selectionCenter - center).rotated(by: a) + center
            return .translation(moved - selectionCenter)
        }
    }

    /// Step that spreads `count` items evenly over `sweepDegrees` (a full circle does not repeat
    /// the first position).
    public static func evenStep(count: Int, sweepDegrees: Double) -> Double {
        guard count >= 2 else { return 0 }
        let full = abs(abs(sweepDegrees) - 360) < 1e-9
        return sweepDegrees / Double(full ? count : count - 1)
    }
}
