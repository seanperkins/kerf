import Foundation

/// 2D affine transform:  x' = a*x + c*y + tx,  y' = b*x + d*y + ty  (CGAffineTransform layout).
public struct Transform2D: Codable, Hashable, Sendable {
    public var a, b, c, d, tx, ty: Double

    /// The uniform scale factor when the transform is a similarity (rotation, mirror, uniform
    /// scale, translation), else nil.
    public var similarityScale: Double? {
        let k2 = a * a + b * b
        let tol = 1e-9 * max(1, k2)
        guard abs(k2 - (c * c + d * d)) <= tol, abs(a * c + b * d) <= tol, k2 > 0 else { return nil }
        return k2.squareRoot()
    }

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = Transform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ v: Vec2) -> Transform2D {
        Transform2D(a: 1, b: 0, c: 0, d: 1, tx: v.x, ty: v.y)
    }
    public static func scale(_ sx: Double, _ sy: Double, about p: Vec2 = .zero) -> Transform2D {
        translation(-p).concatenating(Transform2D(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0))
            .concatenating(translation(p))
    }
    public static func rotation(_ radians: Double, about p: Vec2 = .zero) -> Transform2D {
        let cs = cos(radians), sn = sin(radians)
        return translation(-p).concatenating(Transform2D(a: cs, b: sn, c: -sn, d: cs, tx: 0, ty: 0))
            .concatenating(translation(p))
    }
    /// Mirror across a horizontal (y = p.y) or vertical (x = p.x) axis through `p`.
    public static func mirror(horizontalAxis: Bool, about p: Vec2) -> Transform2D {
        horizontalAxis ? scale(1, -1, about: p) : scale(-1, 1, about: p)
    }

    /// Returns `self` followed by `other` (apply self first).
    public func concatenating(_ o: Transform2D) -> Transform2D {
        Transform2D(a: a * o.a + b * o.c, b: a * o.b + b * o.d,
                    c: c * o.a + d * o.c, d: c * o.b + d * o.d,
                    tx: tx * o.a + ty * o.c + o.tx, ty: tx * o.b + ty * o.d + o.ty)
    }

    public var determinant: Double { a * d - b * c }
    /// True when the transform flips orientation (mirror) — arcs swap direction.
    public var isMirroring: Bool { determinant < 0 }
    /// True when the transform preserves circles (uniform scale + rotation (+ mirror)).
    public var isConformal: Bool {
        abs(a * a + b * b - (c * c + d * d)) < 1e-9 && abs(a * c + b * d) < 1e-9
    }
    public var uniformScale: Double { (abs(determinant)).squareRoot() }

    public var inverted: Transform2D? {
        let det = determinant
        guard abs(det) > 1e-15 else { return nil }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return Transform2D(a: ia, b: ib, c: ic, d: id,
                           tx: -(tx * ia + ty * ic), ty: -(tx * ib + ty * id))
    }

    public func apply(_ p: Vec2) -> Vec2 {
        Vec2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }
    public func applyToVector(_ v: Vec2) -> Vec2 { Vec2(a * v.x + c * v.y, b * v.x + d * v.y) }
}
