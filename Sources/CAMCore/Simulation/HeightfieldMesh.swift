import CADCore
import Foundation

/// Simple RGB colour (0...1) so the core stays free of AppKit/SceneKit.
public struct RGBColor: Hashable, Sendable {
    public var r: Float, g: Float, b: Float
    public init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }

    public func mixed(with o: RGBColor, _ t: Float) -> RGBColor {
        RGBColor(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }
}

/// Colour ramps shared by the 2D overlay and the 3D preview.
public enum DepthColorRamp {
    /// Toolpath overlay: shallow cuts cyan → mid blue → deep magenta/red.
    public static func toolpath(normalizedDepth t: Double) -> RGBColor {
        let stops: [RGBColor] = [RGBColor(0.10, 0.80, 0.90), RGBColor(0.15, 0.35, 0.95),
                                 RGBColor(0.65, 0.20, 0.85), RGBColor(0.90, 0.15, 0.25)]
        return sample(stops, t)
    }

    /// Stock surface: light wood at the top, darker as it gets deeper.
    public static func material(normalizedDepth t: Double) -> RGBColor {
        let stops: [RGBColor] = [RGBColor(0.90, 0.76, 0.54), RGBColor(0.66, 0.47, 0.27),
                                 RGBColor(0.40, 0.26, 0.14)]
        return sample(stops, t)
    }

    static func sample(_ stops: [RGBColor], _ t: Double) -> RGBColor {
        let c = min(max(t.isFinite ? t : 0, 0), 1) * Double(stops.count - 1)
        let i = min(Int(c), stops.count - 2)
        return stops[i].mixed(with: stops[i + 1], Float(c - Double(i)))
    }
}

/// Triangle mesh of the simulated stock: carved top surface plus side walls and bottom.
/// Material frame, Z up: top at z = 0, bottom at z = -thickness.
public struct HeightfieldMesh: Sendable {
    /// xyz triples.
    public var positions: [Float] = []
    /// Unit normals, xyz triples.
    public var normals: [Float] = []
    /// rgb triples.
    public var colors: [Float] = []
    public var indices: [UInt32] = []

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { indices.count / 3 }

    public init() {}

    /// - Parameters:
    ///   - maxVertices: the top surface is decimated (by striding the grid) to stay under this.
    public init(heightfield hf: Heightfield, thickness: Double, maxVertices: Int = 250_000) {
        let stride = Self.stride(columns: hf.columns, rows: hf.rows, maxVertices: maxVertices)
        let xs = Self.samples(count: hf.columns, stride: stride)
        let ys = Self.samples(count: hf.rows, stride: stride)
        let nx = xs.count, ny = ys.count
        let cs = Float(hf.cellSize)
        let thick = Float(max(thickness, 1e-6))
        let width = Float(hf.columns) * cs, height = Float(hf.rows) * cs

        // Grid vertices sit at cell centres, except the outer ring which sits on the stock edge.
        func coord(_ idx: Int, cell: Int, last: Int, extent: Float) -> Float {
            if idx == 0 { return 0 }
            if idx == last { return extent }
            return (Float(cell) + 0.5) * cs
        }
        var gx = [Float](repeating: 0, count: nx), gy = [Float](repeating: 0, count: ny)
        for (k, i) in xs.enumerated() { gx[k] = coord(k, cell: i, last: nx - 1, extent: width) }
        for (k, j) in ys.enumerated() { gy[k] = coord(k, cell: j, last: ny - 1, extent: height) }

        func depth(_ k: Int, _ l: Int) -> Float { hf[xs[k], ys[l]] }

        positions.reserveCapacity((nx * ny + 4 * (nx + ny)) * 3)
        // Top surface.
        for l in 0..<ny {
            for k in 0..<nx {
                let d = depth(k, l)
                positions += [gx[k], gy[l], -d]
                // Central-difference normal of z(x,y) = -depth.
                let kl = max(0, k - 1), kr = min(nx - 1, k + 1)
                let lb = max(0, l - 1), lt = min(ny - 1, l + 1)
                let dzdx = (-depth(kr, l) + depth(kl, l)) / max(gx[kr] - gx[kl], 1e-9)
                let dzdy = (-depth(k, lt) + depth(k, lb)) / max(gy[lt] - gy[lb], 1e-9)
                let n = Self.normalize(-dzdx, -dzdy, 1)
                normals += [n.0, n.1, n.2]
                let c = DepthColorRamp.material(normalizedDepth: Double(d / thick))
                colors += [c.r, c.g, c.b]
            }
        }
        for l in 0..<(ny - 1) {
            for k in 0..<(nx - 1) {
                let a = UInt32(l * nx + k), b = a + 1, c = a + UInt32(nx), d = c + 1
                indices += [a, b, d, a, d, c]
            }
        }

        // Side walls: each edge strip from the carved top down to the bottom.
        let side = RGBColor(0.80, 0.64, 0.42)
        func wall(_ tops: [(Float, Float, Float)], normal: (Float, Float, Float), flip: Bool) {
            let base = UInt32(vertexCount)
            for (x, y, z) in tops {
                positions += [x, y, z, x, y, -thick]
                normals += [normal.0, normal.1, normal.2, normal.0, normal.1, normal.2]
                colors += [side.r, side.g, side.b, side.r, side.g, side.b]
            }
            for q in 0..<(tops.count - 1) {
                let t0 = base + UInt32(2 * q), b0 = t0 + 1, t1 = t0 + 2, b1 = t0 + 3
                indices += flip ? [t0, t1, b0, t1, b1, b0] : [t0, b0, t1, t1, b0, b1]
            }
        }
        wall((0..<nx).map { (gx[$0], 0, -depth($0, 0)) }, normal: (0, -1, 0), flip: false)
        wall((0..<nx).map { (gx[$0], height, -depth($0, ny - 1)) }, normal: (0, 1, 0), flip: true)
        wall((0..<ny).map { (0, gy[$0], -depth(0, $0)) }, normal: (-1, 0, 0), flip: true)
        wall((0..<ny).map { (width, gy[$0], -depth(nx - 1, $0)) }, normal: (1, 0, 0), flip: false)

        // Bottom.
        let base = UInt32(vertexCount)
        for (x, y) in [(Float(0), Float(0)), (width, 0), (width, height), (0, height)] {
            positions += [x, y, -thick]
            normals += [0, 0, -1]
            colors += [side.r, side.g, side.b]
        }
        indices += [base, base + 2, base + 1, base, base + 3, base + 2]
    }

    static func stride(columns: Int, rows: Int, maxVertices: Int) -> Int {
        var s = 1
        while ((columns + s - 1) / s + 1) * ((rows + s - 1) / s + 1) > max(maxVertices, 16) { s += 1 }
        return s
    }

    /// Cell indices sampled along one axis; first and last always included, so the outer
    /// ring hugs the stock edge (index list may repeat the end cell for the edge vertex).
    static func samples(count: Int, stride: Int) -> [Int] {
        var out = Array(Swift.stride(from: 0, to: count, by: stride))
        if out.last != count - 1 { out.append(count - 1) }
        // Leading edge vertex (x = 0) reuses cell 0, trailing edge vertex reuses the last cell.
        return [0] + out + [count - 1]
    }

    static func normalize(_ x: Float, _ y: Float, _ z: Float) -> (Float, Float, Float) {
        let l = (x * x + y * y + z * z).squareRoot()
        return l > 0 ? (x / l, y / l, z / l) : (0, 0, 1)
    }
}
