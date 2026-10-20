import CADCore
import Foundation

/// Move-level view of a `SimulationTimeline` for single-stepping and "run to next retract".
/// A move is one `Move` of a toolpath (an arc is one move even though it is flattened into
/// several steps). Moves that take no time are skipped. Owned by preview.
public struct SimulationMoveIndex: Sendable {
    public struct Span: Hashable, Sendable {
        public var toolpathIndex: Int
        public var moveIndex: Int
        public var startTime: TimeInterval
        public var endTime: TimeInterval
        public var isRapid: Bool
        /// Z gained over the move (positive = tool goes up).
        public var rise: Double
        public var start: Vec3
        public var end: Vec3

        /// A rapid that lifts the tool: the end of a cutting sequence.
        public var isRetract: Bool { isRapid && rise > 1e-9 }
    }

    public let spans: [Span]
    public let totalTime: TimeInterval
    static let epsilon: TimeInterval = 1e-9

    public init(timeline: SimulationTimeline) {
        var out: [Span] = []
        for step in timeline.steps {
            let s = step.segment
            if var last = out.last, last.toolpathIndex == step.toolpathIndex, last.moveIndex == s.moveIndex {
                last.endTime = step.endTime
                last.end = s.end
                last.rise = s.end.z - last.start.z
                out[out.count - 1] = last
            } else {
                out.append(Span(toolpathIndex: step.toolpathIndex, moveIndex: s.moveIndex, startTime: step.startTime,
                                endTime: step.endTime, isRapid: s.isRapid, rise: s.end.z - s.start.z,
                                start: s.start, end: s.end))
            }
        }
        spans = out.filter { $0.endTime - $0.startTime > Self.epsilon }
        totalTime = timeline.totalTime
    }

    /// Index of the move in progress at `time` (the next one during a pause), or nil after the end.
    public func spanIndex(at time: TimeInterval) -> Int? {
        var lo = 0, hi = spans.count
        while lo < hi { // first span ending after `time`
            let mid = (lo + hi) / 2
            if spans[mid].endTime > time + Self.epsilon { hi = mid } else { lo = mid + 1 }
        }
        return lo < spans.count ? lo : nil
    }

    /// End of the move in progress (or of the next move when exactly at a boundary).
    public func nextBoundary(after time: TimeInterval) -> TimeInterval {
        guard let i = spanIndex(at: time) else { return totalTime }
        return spans[i].endTime
    }

    /// Start of the move in progress, or of the previous move when already at its start.
    public func previousBoundary(before time: TimeInterval) -> TimeInterval {
        var best: TimeInterval = 0
        for s in spans {
            if s.startTime < time - Self.epsilon { best = s.startTime } else { break }
        }
        return best
    }

    /// End of the next retract (a rapid that lifts the tool) that finishes after `time`.
    public func nextRetract(after time: TimeInterval) -> TimeInterval {
        guard let i = spanIndex(at: time) else { return totalTime }
        return spans[i...].first(where: \.isRetract)?.endTime ?? totalTime
    }
}
