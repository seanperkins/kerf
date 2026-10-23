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
    ///   - toolChangeSeconds: allowance added whenever the machine stops between toolpaths: the tool
    ///     differs from the previous toolpath's, or that toolpath ends in an operator pause.
    ///   - motion: acceleration model and calibration factor (default: length / feed).
    public init(toolpaths: [Toolpath], rapidRate: Double, toolChangeSeconds: TimeInterval = 0,
                arcTolerance: Double = 0.001, motion: MachineMotion = .instant) {
        // Pass 1: flatten every move into pieces, remembering pauses (dwells, tool changes)
        // that come before each piece.
        var segs: [(toolpath: Int, seg: MotionSegment)] = []
        var pieces: [MotionPlanner.Piece] = []
        var pauseBefore: [TimeInterval] = []
        var pendingPause: TimeInterval = 0
        var stopPending = true
        var pos: Vec3?
        let rapid = max(rapidRate, 1e-9)
        let scale = motion.effectiveScale
        for (ti, tp) in toolpaths.enumerated() {
            if ti > 0, ToolpathStats.stopsBefore(tp, after: toolpaths[ti - 1]) {
                pendingPause += toolChangeSeconds
                stopPending = true
            }
            // Between toolpaths the tool travels from where the last one ended.
            var moveStart = pos
            for (k, move) in tp.moves.enumerated() {
                if case .dwell(let s) = move {
                    pendingPause += max(0, s) * scale
                    stopPending = true
                    continue
                }
                guard let target = move.target else { continue }
                let from = moveStart ?? target
                let flat = MotionPath.segments(of: [move], startingAt: from, arcTolerance: arcTolerance)
                // Time arcs by their true (helical) length, not the shorter chord sum.
                var stretch = 1.0
                if case .arcCW(_, let c, _) = move { stretch = Self.arcStretch(flat, from, target, c, true) }
                if case .arcCCW(_, let c, _) = move { stretch = Self.arcStretch(flat, from, target, c, false) }
                for var seg in flat {
                    seg.moveIndex = k
                    let rate = seg.isRapid ? rapid : ((seg.feed ?? 0) > 0 ? seg.feed! : rapid)
                    segs.append((ti, seg))
                    pieces.append(MotionPlanner.Piece(start: seg.start, end: seg.end,
                                                      length: seg.length * stretch, rate: rate,
                                                      stopBefore: stopPending))
                    pauseBefore.append(pendingPause)
                    pendingPause = 0
                    stopPending = false
                }
                moveStart = target
            }
            pos = moveStart
        }
        // Pass 2: plan speeds and lay the pieces out on the time axis.
        let durations = MotionPlanner.durations(pieces, motion: motion)
        var steps: [Step] = []
        steps.reserveCapacity(segs.count)
        var t: TimeInterval = 0
        for i in segs.indices {
            t += pauseBefore[i]
            let dt = durations[i] * scale
            steps.append(Step(toolpathIndex: segs[i].toolpath, segment: segs[i].seg, startTime: t, endTime: t + dt))
            t += dt
        }
        t += pendingPause // trailing dwell / tool change with no motion after it
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

/// Machining-time estimate: feeds, rapids, dwells and tool changes, optionally with an
/// acceleration model and calibration factor (`MachineMotion`). Owned by preview.
public enum MachiningTimeEstimator {
    /// Default allowance for a manual tool change (stop, swap collet, re-zero Z).
    public static let defaultToolChangeSeconds: TimeInterval = 90

    /// - Parameters:
    ///   - rapidRate: machine rapid speed in document units per minute.
    ///   - toolChangeSeconds: added for every change of tool between consecutive toolpaths.
    ///   - motion: acceleration model and calibration factor (default: length / feed).
    public static func estimate(_ toolpaths: [Toolpath], rapidRate: Double,
                                toolChangeSeconds: TimeInterval = defaultToolChangeSeconds,
                                motion: MachineMotion = .instant) -> TimeInterval {
        SimulationTimeline(toolpaths: toolpaths, rapidRate: rapidRate,
                           toolChangeSeconds: toolChangeSeconds, arcTolerance: 0.001, motion: motion).totalTime
    }

    /// "1h 05m 12s" / "4m 03s" / "12s". `Int(_:)` traps beyond its range (a tool-change allowance or a dwell typed as
    /// 1e300 reached it), so a value no job takes shows "over 1,000,000 h" and none (NaN, below -3.6e9 s) a dash.
    public static func format(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN, seconds >= -3_600_000_000 else { return "—" }
        guard seconds <= 3_600_000_000 else { return "over 1,000,000 h" }
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, sec) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }
}
