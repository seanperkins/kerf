import CADCore
import Foundation

/// Seekable material-removal simulation over a `SimulationTimeline`.
/// Seeking forward carves incrementally; seeking backward restores the nearest checkpoint
/// (snapshots taken every `checkpointInterval` steps) and replays from there.
public struct SimulationPlayer: Sendable {
    public let timeline: SimulationTimeline
    public private(set) var simulator: MaterialSimulator
    /// Fully carved steps.
    public private(set) var appliedSteps = 0
    /// Fraction of step `appliedSteps` carved on top (shows a move in progress).
    public private(set) var partialFraction = 0.0
    public private(set) var currentTime: TimeInterval = 0

    private let blank: Heightfield
    private var checkpoints: [Int: Heightfield] = [:]
    public let checkpointInterval: Int

    public init(job: JobSetup, toolpaths: [Toolpath], rapidRate: Double, cellSize: Double,
                toolChangeSeconds: TimeInterval = MachiningTimeEstimator.defaultToolChangeSeconds,
                maxCheckpoints: Int = 12, motion: MachineMotion = .instant) {
        let sim = MaterialSimulator(job: job, cellSize: cellSize)
        simulator = sim
        blank = sim.heightfield
        timeline = SimulationTimeline(toolpaths: toolpaths, rapidRate: rapidRate,
                                      toolChangeSeconds: toolChangeSeconds,
                                      arcTolerance: sim.arcTolerance, motion: motion)
        checkpointInterval = max(64, timeline.steps.count / max(1, maxCheckpoints))
    }

    public var heightfield: Heightfield { simulator.heightfield }
    public var isAtEnd: Bool { appliedSteps >= timeline.steps.count }

    /// Brings the stock to its state at `time` (seconds from the job start).
    public mutating func seek(to time: TimeInterval) {
        let target = timeline.position(at: time)
        currentTime = min(max(time, 0), timeline.totalTime)
        let behind = target.step < appliedSteps
            || (target.step == appliedSteps && target.fraction < partialFraction)
        if behind { restore(atOrBefore: target.step) }
        while appliedSteps < target.step {
            let s = timeline.steps[appliedSteps]
            simulator.apply(s.segment, shape: timeline.shapes[s.toolpathIndex])
            appliedSteps += 1
            partialFraction = 0
            if appliedSteps % checkpointInterval == 0, checkpoints[appliedSteps] == nil {
                checkpoints[appliedSteps] = simulator.heightfield
            }
        }
        if target.step < timeline.steps.count, target.fraction > 0 {
            let s = timeline.steps[target.step]
            simulator.apply(s.segment, shape: timeline.shapes[s.toolpathIndex], fraction: target.fraction)
            partialFraction = target.fraction
        }
    }

    /// Carves everything.
    public mutating func runToEnd() { seek(to: timeline.totalTime) }

    private mutating func restore(atOrBefore step: Int) {
        let best = checkpoints.keys.filter { $0 <= step }.max()
        if let best, let hf = checkpoints[best] {
            simulator.heightfield = hf
            appliedSteps = best
        } else {
            simulator.heightfield = blank
            appliedSteps = 0
        }
        partialFraction = 0
    }
}
