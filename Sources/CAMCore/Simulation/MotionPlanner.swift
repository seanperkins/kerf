import CADCore
import Foundation

/// How the time estimate models the machine's motion. Owned by preview.
///
/// With `acceleration` = 0 every move runs at its programmed feed from the first instant
/// (the classic length / feed estimate). With an acceleration the estimate follows a
/// trapezoidal velocity profile: the machine speeds up and slows down at `acceleration`, slows
/// at corners (junction-deviation cornering, the model most hobby controllers use) and stops
/// at dwells and tool changes. `timeScale` is a user calibration factor applied to all motion
/// and dwell time (e.g. 1.15 when real jobs run 15 % longer than estimated).
public struct MachineMotion: Hashable, Sendable {
    /// Units per second². 0 = instantaneous feeds.
    public var acceleration: Double
    /// Corner tolerance in units: larger values let the machine take corners faster.
    public var junctionDeviation: Double
    /// Multiplier on motion and dwell time (tool-change allowances are not scaled).
    public var timeScale: Double

    public init(acceleration: Double = 0, junctionDeviation: Double = 0.002, timeScale: Double = 1) {
        self.acceleration = acceleration
        self.junctionDeviation = junctionDeviation
        self.timeScale = timeScale
    }

    /// Length / feed, no scaling.
    public static let instant = MachineMotion()

    var effectiveScale: Double { timeScale.isFinite && timeScale > 0 ? timeScale : 1 }
}

/// Velocity planner: entry/exit speeds per straight piece and the resulting durations.
public enum MotionPlanner {
    /// One straight piece of motion.
    public struct Piece: Hashable, Sendable {
        public var start: Vec3
        public var end: Vec3
        /// Distance travelled (may exceed the chord for flattened arcs).
        public var length: Double
        /// Programmed speed, units per minute.
        public var rate: Double
        /// The machine is at rest before this piece (program start, dwell, tool change).
        public var stopBefore: Bool

        public init(start: Vec3, end: Vec3, length: Double? = nil, rate: Double, stopBefore: Bool = false) {
            self.start = start; self.end = end
            self.length = length ?? start.distance(to: end)
            self.rate = rate; self.stopBefore = stopBefore
        }
    }

    /// Seconds for each piece (unscaled). The machine starts and ends at rest.
    public static func durations(_ pieces: [Piece], motion: MachineMotion) -> [TimeInterval] {
        let n = pieces.count
        guard n > 0 else { return [] }
        let a = motion.acceleration
        // Speeds in units/second.
        let vmax = pieces.map { max($0.rate, 1e-9) / 60 }
        guard a > 0, a.isFinite else {
            return pieces.indices.map { pieces[$0].length / vmax[$0] }
        }

        // Entry speed limit at each piece start; entry[n] is the final exit (0).
        var entry = [Double](repeating: 0, count: n + 1)
        var prevDir: Vec3?
        for i in 0..<n {
            let p = pieces[i]
            let d = p.end - p.start
            let dir: Vec3? = d.length > 1e-12 ? d.normalized : nil
            if p.stopBefore || i == 0 {
                entry[i] = 0
                prevDir = nil
            } else if dir == nil {
                // Zero-length piece: carries the previous speed limit through.
                entry[i] = min(vmax[i - 1], vmax[i])
            } else if let pd = prevDir, let dir {
                entry[i] = min(junctionSpeed(pd, dir, a: a, deviation: motion.junctionDeviation),
                               vmax[i - 1], vmax[i])
            } else {
                entry[i] = 0
            }
            if let dir { prevDir = dir }
        }
        // Backward pass: must be able to slow down to the next entry.
        for i in stride(from: n - 1, through: 0, by: -1) {
            entry[i] = min(entry[i], (entry[i + 1] * entry[i + 1] + 2 * a * pieces[i].length).squareRoot())
        }
        // Forward pass: cannot exit faster than reachable from the entry.
        for i in 0..<n {
            entry[i + 1] = min(entry[i + 1], (entry[i] * entry[i] + 2 * a * pieces[i].length).squareRoot())
        }
        return (0..<n).map { trapezoidTime(length: pieces[$0].length, entry: entry[$0], exit: entry[$0 + 1],
                                           cruise: vmax[$0], acceleration: a) }
    }

    /// Junction-deviation cornering speed between unit directions `a` and `b`.
    static func junctionSpeed(_ u: Vec3, _ w: Vec3, a: Double, deviation: Double) -> Double {
        let cosTheta = -u.dot(w) // θ = angle between the reversed incoming and the outgoing direction
        if cosTheta <= -0.999999 { return .infinity } // straight on
        if cosTheta >= 0.999999 { return 0 }          // full reversal
        let sinHalf = (0.5 * (1 - cosTheta)).squareRoot()
        guard sinHalf < 1 else { return .infinity }
        return (a * max(deviation, 0) * sinHalf / (1 - sinHalf)).squareRoot()
    }

    /// Time to cover `length` starting at `entry` and ending at `exit` without exceeding
    /// `cruise`, accelerating/decelerating at `acceleration`.
    public static func trapezoidTime(length: Double, entry: Double, exit: Double, cruise: Double,
                                     acceleration a: Double) -> TimeInterval {
        guard length > 0 else { return 0 }
        let vi = min(entry, cruise), vo = min(exit, cruise)
        let accelDist = (cruise * cruise - vi * vi) / (2 * a)
        let decelDist = (cruise * cruise - vo * vo) / (2 * a)
        if accelDist + decelDist <= length {
            return (cruise - vi) / a + (cruise - vo) / a + (length - accelDist - decelDist) / cruise
        }
        // Never reaches cruise: triangular profile peaking at vp.
        let vp = max((a * length + (vi * vi + vo * vo) / 2).squareRoot(), max(vi, vo))
        return max(0, (vp - vi) / a) + max(0, (vp - vo) / a)
    }
}
