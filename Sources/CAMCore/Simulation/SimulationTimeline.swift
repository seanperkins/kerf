import CADCore
import Foundation

/// All toolpaths of a job laid out on one time axis (seconds), segment by segment.
/// Drives the time estimate and the preview's play/scrub control.
public struct SimulationTimeline: Sendable {
    public struct Step: Hashable, Sendable {
        public var toolpathIndex: Int
        public var segment: MotionSegment
        public var startTime: TimeInterval
        public var endTime: TimeInterval
        public var duration: TimeInterval { endTime - startTime }
    }

    public let steps: [Step]
    /// Cutter profile per toolpath (same order as the input toolpaths).
    public let shapes: [ToolShape]
    public let totalTime: TimeInterval

    /// - Parameters:
    ///   - rapidRate: rapid speed in document units per minute.
    ///   - toolChangeSeconds: allowance added whenever the tool differs from the previous toolpath.
    public init(toolpaths: [Toolpath], rapidRate: Double, toolChangeSeconds: TimeInterval = 0,
                arcTolerance: Double = 0.001) {
        var steps: [Step] = []
        var t: TimeInterval = 0
        var pos: Vec3?
        var lastTool: Tool?
        let rapid = max(rapidRate, 1e-9)
        for (ti, tp) in toolpaths.enumerated() {
            if let last = lastTool, last.id != tp.tool.id || last.number != tp.tool.number {
                t += toolChangeSeconds
            }
            lastTool = tp.tool
            // Between toolpaths the tool travels from where the last one ended.
            var moveStart = pos
            for (k, move) in tp.moves.enumerated() {
                if case .dwell(let s) = move { t += max(0, s); continue }
                guard let target = move.target else { continue }
                let from = moveStart ?? target
                let segs = MotionPath.segments(of: [move], startingAt: from, arcTolerance: arcTolerance)
                // Time arcs by their true (helical) length, not the shorter chord sum.
                var stretch = 1.0
                if case .arcCW(_, let c, _) = move { stretch = Self.arcStretch(segs, from, target, c, true) }
                if case .arcCCW(_, let c, _) = move { stretch = Self.arcStretch(segs, from, target, c, false) }
                for var seg in segs {
                    seg.moveIndex = k
                    let rate = seg.isRapid ? rapid : ((seg.feed ?? 0) > 0 ? seg.feed! : rapid)
                    let dt = seg.length * stretch / rate * 60
                    steps.append(Step(toolpathIndex: ti, segment: seg, startTime: t, endTime: t + dt))
                    t += dt
                }
                moveStart = target
            }
            pos = moveStart
        }
        self.steps = steps
        shapes = toolpaths.map { ToolShape(tool: $0.tool) }
        totalTime = t
    }

    static func arcStretch(_ segs: [MotionSegment], _ from: Vec3, _ to: Vec3, _ center: Vec2,
                           _ clockwise: Bool) -> Double {
        let chords = segs.reduce(0) { $0 + $1.length }
        guard chords > 1e-12 else { return 1 }
        let r = ((from.xy - center).length + (to.xy - center).length) / 2
        let sweep = Flattening.arcSweep(from: from.xy, to: to.xy, center: center, clockwise: clockwise)
        let planar = abs(sweep) * r
        let dz = to.z - from.z
        return (planar * planar + dz * dz).squareRoot() / chords
    }

    /// Index of the step in progress at `time`, and how far through it (0...1).
    /// Returns (steps.count, 0) at or after the end.
    public func position(at time: TimeInterval) -> (step: Int, fraction: Double) {
        guard !steps.isEmpty else { return (0, 0) }
        if time >= totalTime { return (steps.count, 0) }
        if time <= 0 { return (0, 0) }
        // First step whose end is after `time`.
        var lo = 0, hi = steps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if steps[mid].endTime > time { hi = mid } else { lo = mid + 1 }
        }
        let s = steps[lo]
        let frac = s.duration > 0 ? (time - s.startTime) / s.duration : 1
        return (lo, min(max(frac, 0), 1))
    }

    /// Tool tip (machine coordinates) and active toolpath index at `time`.
    public func toolPosition(at time: TimeInterval) -> (point: Vec3, toolpathIndex: Int)? {
        guard let last = steps.last else { return nil }
        let p = position(at: time)
        if p.step >= steps.count { return (last.segment.end, last.toolpathIndex) }
        let s = steps[p.step]
        return (s.segment.point(at: p.fraction), s.toolpathIndex)
    }
}

/// Machining-time estimate (feeds + rapids, no acceleration model). Owned by preview.
public enum MachiningTimeEstimator {
    /// Default allowance for a manual tool change (stop, swap collet, re-zero Z).
    public static let defaultToolChangeSeconds: TimeInterval = 90

    /// - Parameters:
    ///   - rapidRate: machine rapid speed in document units per minute.
    ///   - toolChangeSeconds: added for every change of tool between consecutive toolpaths.
    public static func estimate(_ toolpaths: [Toolpath], rapidRate: Double,
                                toolChangeSeconds: TimeInterval = defaultToolChangeSeconds) -> TimeInterval {
        SimulationTimeline(toolpaths: toolpaths, rapidRate: rapidRate,
                           toolChangeSeconds: toolChangeSeconds, arcTolerance: 0.001).totalTime
    }

    /// "1h 05m 12s" / "4m 03s" / "12s".
    public static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, sec) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }
}
