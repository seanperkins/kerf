import Foundation

/// Shear and envelope (four-corner) distortion.
public enum Distort {
    /// Shear about `pivot`: `xDegrees` slants vertical lines (x shifts with y), `yDegrees` slants
    /// horizontal lines (y shifts with x).
    public static func shear(xDegrees: Double, yDegrees: Double, about pivot: Vec2) -> Transform2D {
        let sx = tan(xDegrees * .pi / 180), sy = tan(yDegrees * .pi / 180)
        return Transform2D.translation(-pivot)
            .concatenating(Transform2D(a: 1, b: sy, c: sx, d: 1, tx: 0, ty: 0))
            .concatenating(.translation(pivot))
    }

    /// Bilinear map of `box` onto the quad (lowerLeft, lowerRight, upperRight, upperLeft).
    public static func envelopeMap(_ p: Vec2, box: Rect2, quad: [Vec2]) -> Vec2 {
        guard quad.count == 4, box.width > 0, box.height > 0 else { return p }
        let u = (p.x - box.min.x) / box.width, v = (p.y - box.min.y) / box.height
        let bottom = quad[0].lerp(to: quad[1], u), top = quad[3].lerp(to: quad[2], u)
        return bottom.lerp(to: top, v)
    }

    /// Paths distorted by the envelope (flattened, mapped, then refitted with lines and arcs).
    public static func envelope(_ paths: [Path], box: Rect2, quad: [Vec2], tolerance: Double) -> [Path] {
        paths.map { path in
            let pts = path.flattened(tolerance: max(tolerance / 4, 1e-6)).map { envelopeMap($0, box: box, quad: quad) }
            return CurveFit.fit(Path(points: pts, closed: path.isClosed), tolerance: tolerance)
        }
    }
}
