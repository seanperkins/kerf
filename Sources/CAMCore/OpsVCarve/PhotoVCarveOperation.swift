import CADCore
import Foundation

/// PhotoVCarve: parallel grooves across the picture, each cut by the V-bit at a depth that
/// makes the groove's top width proportional to the image darkness at that point
/// (black = `lineSpacing` wide, so neighbouring grooves just meet).
///
/// Groove width w at depth d for a bit with tip radius rt and half-angle slope t:
/// w = 2·(rt + d·t), so d = max(0, w/2 − rt) / t.
public struct PhotoVCarveOperation: ToolpathOperation {
    public static let kind = OperationKind.photoVCarve
    public var setup: OperationSetup
    public var params: PhotoVCarveParameters

    public init(setup: OperationSetup, params: PhotoVCarveParameters = PhotoVCarveParameters()) {
        self.setup = setup
        self.params = params
    }

    public func generate(in context: CAMContext) throws -> [Toolpath] {
        let p = params
        guard let image = p.image, image.width > 0, image.height > 0,
              image.pixels.count >= image.width * image.height else {
            throw CAMError.invalidParameter("choose an image for the photo V-carve")
        }
        guard p.width > 0, p.lineSpacing > 0 else {
            throw CAMError.invalidParameter("picture width and line spacing must be positive")
        }
        guard p.startDepth >= 0, p.minDepth >= 0 else {
            throw CAMError.invalidParameter("start depth and minimum depth must not be negative")
        }
        let vbit = try context.tool(setup.toolID)
        let slope = try VCarveEngine.validateVBit(vbit)
        let tipRadius = max(0, vbit.tipDiameter / 2)
        let toolLimit = max(0, vbit.radius - tipRadius) / slope
        let fullDepth = min(max(0, p.lineSpacing / 2 - tipRadius) / slope, toolLimit)
        guard fullDepth > p.minDepth else {
            throw CAMError.invalidParameter("line spacing is too small for this bit's tip")
        }

        let strokes = Self.strokes(params: p, image: image, slope: slope, tipRadius: tipRadius, fullDepth: fullDepth,
                                   step: min(p.lineSpacing / 4, context.units == .inch ? 0.02 : 0.5))
            .map { VCarveStroke(points: VCarveStrokes.simplified($0.points, tolerance: context.tolerance), isClosed: false) }
        var metadata = ["maxDepth": String(format: "%.4f", p.startDepth + fullDepth),
                        "grooves": "\(strokes.count)"]
        if fullDepth < max(0, p.lineSpacing / 2 - tipRadius) / slope - 1e-9 {
            metadata["warning"] = "Line spacing is wider than the V-bit; black areas are limited to its full width"
        }
        guard let tp = VCarveEngine.toolpath(name: setup.name, operationID: setup.id, kind: Self.kind, tool: vbit,
                                             passes: [strokes], context: context, metadata: metadata) else {
            throw CAMError.invalidGeometry("the picture is too light to carve anything")
        }
        return [tp]
    }

    /// Grooves in cutting order (alternating direction line by line).
    static func strokes(params p: PhotoVCarveParameters, image: GrayImage, slope: Double, tipRadius: Double,
                        fullDepth: Double, step: Double) -> [VCarveStroke] {
        let w = p.width, h = p.height
        let rad = p.angle * .pi / 180
        let dir = Vec2(cos(rad), sin(rad)), normal = dir.perpendicular
        let centre = p.origin + Vec2(w / 2, h / 2)
        let half = (w * w + h * h).squareRoot() / 2
        let samples = max(2, Int((2 * half / step).rounded(.up)))
        var out: [VCarveStroke] = []
        var line = 0
        var t = -half + p.lineSpacing / 2
        while t <= half {
            var pts: [Vec3] = []
            var lineStrokes: [VCarveStroke] = []
            func flush() {
                if pts.count >= 2 { lineStrokes.append(VCarveStroke(points: pts, isClosed: false)) }
                pts = []
            }
            for k in 0...samples {
                let q = centre + normal * t + dir * (-half + 2 * half * Double(k) / Double(samples))
                let u = (q.x - p.origin.x) / w, v = (q.y - p.origin.y) / h
                guard u >= 0, u <= 1, v >= 0, v <= 1 else { flush(); continue }
                var dark = 1 - image.brightness(u: u, v: v)
                if p.invert { dark = 1 - dark }
                let width = dark * p.lineSpacing
                let depth = min(max(0, width / 2 - tipRadius) / slope, fullDepth)
                if depth < p.minDepth { flush(); continue }
                pts.append(Vec3(q, z: p.startDepth + depth))
            }
            flush()
            if line % 2 == 1 {
                lineStrokes = lineStrokes.reversed().map { VCarveStroke(points: $0.points.reversed(), isClosed: false) }
            }
            out += lineStrokes
            line += 1
            t += p.lineSpacing
        }
        return out
    }
}

extension GrayImage {
    /// Bilinear brightness (0 = black … 1 = white) at normalised picture coordinates
    /// (u right, v up; v = 1 is the image's top row).
    public func brightness(u: Double, v: Double) -> Double {
        guard width > 0, height > 0 else { return 1 }
        let x = min(max(u * Double(width) - 0.5, 0), Double(width - 1))
        let y = min(max((1 - v) * Double(height) - 0.5, 0), Double(height - 1))
        let x0 = Int(x), y0 = Int(y)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = x - Double(x0), fy = y - Double(y0)
        return pixels.withUnsafeBytes { raw -> Double in
            let b = raw.bindMemory(to: UInt8.self)
            func px(_ i: Int, _ j: Int) -> Double { Double(b[j * width + i]) / 255 }
            let top = px(x0, y0) * (1 - fx) + px(x1, y0) * fx
            let bottom = px(x0, y1) * (1 - fx) + px(x1, y1) * fx
            return top * (1 - fy) + bottom * fy
        }
    }
}
