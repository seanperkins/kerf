import Foundation

/// Fills a closed boundary with a generated pattern of open vectors (for carving textures).
public enum VectorTexture {
    public enum Pattern: String, Codable, CaseIterable, Sendable { case lines, waves, zigzag }

    public struct Options: Sendable {
        public var pattern: Pattern = .waves
        /// Distance between neighbouring lines.
        public var spacing: Double = 0.25
        /// Direction of the lines in degrees.
        public var angle: Double = 0
        /// Waves/zigzag: peak height and repeat length.
        public var amplitude: Double = 0.1
        public var wavelength: Double = 1
        /// 0…1: random variation of each line's amplitude and phase (seeded, repeatable).
        public var variation: Double = 0
        public var seed: UInt64 = 1
        public init() {}
    }

    /// Pattern lines clipped to the inside of `boundary` (closed paths, even-odd).
    public static func fill(_ boundary: [Path], options o: Options, tolerance: Double) -> [Path] {
        let closed = boundary.filter(\.isClosed)
        guard !closed.isEmpty, o.spacing > 0 else { return [] }
        let box = Rect2(points: closed.flatMap { $0.flattened(tolerance: tolerance) })
        guard !box.isEmpty else { return [] }
        let c = box.center
        let half = (box.size.length / 2) + o.amplitude + o.spacing
        let rot = Transform2D.rotation(o.angle * .pi / 180, about: .zero).concatenating(.translation(c))
        var rng = SplitMix(seed: o.seed)
        var out: [Path] = []
        // Lines sit half a spacing off the centre, so symmetric boundaries are not traced along their edges.
        var y = -((half / o.spacing).rounded(.down) + 0.5) * o.spacing
        while y <= half {
            let amp = o.amplitude * (1 + o.variation * (rng.unit() * 2 - 1) * 0.5)
            let phase = o.variation * rng.unit() * 2 * .pi
            let line = Path(points: wave(from: -half, to: half, y: y, pattern: o.pattern, amplitude: amp,
                                         wavelength: o.wavelength, phase: phase, tolerance: tolerance), closed: false)
                .transformed(rot)
            out += Trim.toBoundary(line, boundary: closed, keepInside: true, tolerance: tolerance)
            y += o.spacing
        }
        return out
    }

    static func wave(from x0: Double, to x1: Double, y: Double, pattern: Pattern, amplitude: Double, wavelength: Double,
                     phase: Double, tolerance: Double) -> [Vec2] {
        switch pattern {
        case .lines:
            return [Vec2(x0, y), Vec2(x1, y)]
        case .zigzag:
            guard wavelength > 0 else { return [Vec2(x0, y), Vec2(x1, y)] }
            var pts: [Vec2] = []
            var x = x0 - phase / (2 * .pi) * wavelength
            var up = true
            while x <= x1 + wavelength {
                pts.append(Vec2(x, y + (up ? amplitude : -amplitude)))
                up.toggle()
                x += wavelength / 2
            }
            return pts
        case .waves:
            guard wavelength > 0 else { return [Vec2(x0, y), Vec2(x1, y)] }
            // Enough samples per wavelength to stay within the tolerance.
            let k = 2 * Double.pi / wavelength
            let maxStep = amplitude > 0 ? max(sqrt(8 * tolerance / (amplitude * k * k)), wavelength / 200) : (x1 - x0)
            let n = max(2, Int(((x1 - x0) / maxStep).rounded(.up)))
            return (0...n).map { i in
                let x = x0 + (x1 - x0) * Double(i) / Double(n)
                return Vec2(x, y + amplitude * sin(k * x + phase))
            }
        }
    }

    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }
}
