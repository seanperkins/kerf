// Machining-time estimate settings (acceleration, calibration factor, tool-change allowance).
// Owned by preview. Stored per user in UserDefaults because they describe the machine and the
// person running it, not one job.
import CADCore
import CAMCore
import Combine
import Foundation

struct TimeEstimateSettings: Hashable, Sendable {
    /// Model acceleration and cornering (off = length / feed).
    var useAcceleration = true
    /// Machine acceleration in inches per second² (converted for mm documents).
    var accelerationInchPerSec2 = TimeEstimateSettings.defaultAcceleration
    /// Calibration multiplier on motion and dwell time.
    var scale = 1.0
    /// Allowance per manual tool change.
    var toolChangeSeconds = MachiningTimeEstimator.defaultToolChangeSeconds

    /// Conservative acceleration for a stepper-driven gantry router (≈ 0.04 g). The user
    /// calibrates the final number with `scale` against a real run.
    static let defaultAcceleration = 15.0
    /// Junction deviation (corner tolerance) in inches.
    static let junctionDeviationInch = 0.002
    static let scaleRange = 0.2...5.0
    /// The allowance per tool change, in seconds: up to a day.
    static let toolChangeRange = 0.0...86_400.0

    static let useAccelerationKey = "loftline.time.useAcceleration"
    static let accelerationKey = "loftline.time.accelerationInchPerSec2"
    static let scaleKey = "loftline.time.scale"
    static let toolChangeKey = "loftline.time.toolChangeSeconds"

    static func load(from defaults: UserDefaults = .standard) -> TimeEstimateSettings {
        var s = TimeEstimateSettings()
        if defaults.object(forKey: useAccelerationKey) != nil { s.useAcceleration = defaults.bool(forKey: useAccelerationKey) }
        if let v = defaults.object(forKey: accelerationKey) as? Double, v > 0, v.isFinite { s.accelerationInchPerSec2 = v }
        if let v = defaults.object(forKey: scaleKey) as? Double, v.isFinite { s.scale = clampScale(v) }
        if let v = defaults.object(forKey: toolChangeKey) as? Double { s.toolChangeSeconds = clampToolChange(v) }
        return s
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(useAcceleration, forKey: Self.useAccelerationKey)
        defaults.set(accelerationInchPerSec2, forKey: Self.accelerationKey)
        defaults.set(scale, forKey: Self.scaleKey)
        defaults.set(toolChangeSeconds, forKey: Self.toolChangeKey)
    }

    /// Motion model in document `units`.
    func motion(units: LengthUnit) -> MachineMotion {
        let f = LengthUnit.inch.factor(to: units)
        return MachineMotion(acceleration: useAcceleration ? max(0, accelerationInchPerSec2) * f : 0,
                             junctionDeviation: Self.junctionDeviationInch * f,
                             timeScale: Self.clampScale(scale))
    }

    /// Estimated seconds for `toolpaths` (document units, rapid rate in units/minute). With
    /// `toolChanges` false, motion and dwell only: no allowance for the tool changes between them.
    func estimate(_ toolpaths: [Toolpath], rapidRate: Double, units: LengthUnit, toolChanges: Bool = true) -> TimeInterval {
        MachiningTimeEstimator.estimate(toolpaths, rapidRate: rapidRate, toolChangeSeconds: toolChanges ? toolChangeSeconds : 0,
                                        motion: motion(units: units))
    }

    /// Scale that makes the estimate of a job match how long it really took.
    /// - Parameters:
    ///   - motionSeconds: the job's motion + dwell time at scale 1.
    ///   - fixedSeconds: unscaled time (tool-change allowances).
    ///   - actualSeconds: measured run time.
    static func calibratedScale(motionSeconds: Double, fixedSeconds: Double, actualSeconds: Double) -> Double? {
        guard motionSeconds > 0, actualSeconds > fixedSeconds else { return nil }
        return clampScale((actualSeconds - fixedSeconds) / motionSeconds)
    }

    /// Splits a job's estimate into scaled motion time (at scale 1) and fixed time.
    func calibrationParts(_ toolpaths: [Toolpath], rapidRate: Double, units: LengthUnit)
        -> (motion: Double, fixed: Double) {
        var one = self, two = self
        one.scale = 1; two.scale = 2
        let t1 = one.estimate(toolpaths, rapidRate: rapidRate, units: units)
        let t2 = two.estimate(toolpaths, rapidRate: rapidRate, units: units)
        return (t2 - t1, max(0, 2 * t1 - t2))
    }

    static func clampScale(_ v: Double) -> Double { min(max(v, scaleRange.lowerBound), scaleRange.upperBound) }

    /// `v` within `toolChangeRange`; the default for NaN (a field can hand one over).
    static func clampToolChange(_ v: Double) -> Double {
        v.isNaN ? MachiningTimeEstimator.defaultToolChangeSeconds : min(max(v, toolChangeRange.lowerBound), toolChangeRange.upperBound)
    }
}

/// Live, observable copy of the settings for the UI. Writes go straight to UserDefaults so
/// background calculations (`ToolpathCalculator`) see them.
@MainActor
final class TimeEstimateStore: ObservableObject {
    static let shared = TimeEstimateStore()

    @Published var settings: TimeEstimateSettings {
        didSet { if settings != oldValue { settings.save() } }
    }

    init(defaults: UserDefaults = .standard) { settings = .load(from: defaults) }
}

extension LoftLineDocument {
    /// Estimate for `toolpaths` with the user's time-estimate settings and this document's post.
    func estimateSeconds(_ toolpaths: [Toolpath]) -> TimeInterval {
        TimeEstimateSettings.load().estimate(toolpaths, rapidRate: rapidRateInDocumentUnits, units: units)
    }

    /// The job summary of the output project with `settings` (the live store's, so the sidebar and
    /// the preview agree), timed over the toolpaths in program order and reused until something it
    /// is made from changes.
    func jobSummary(groupByTool: Bool, settings: TimeEstimateSettings) -> JobSummary {
        jobSummaryMemo.summary(operations: outputProject.operations, results: results, groupByTool: groupByTool,
                               settings: settings, rapidRate: rapidRateInDocumentUnits, units: units)
    }

    /// Recomputes the stored per-operation estimates (after the settings or machine change).
    func refreshTimeEstimates() {
        let s = TimeEstimateSettings.load()
        let rapid = rapidRateInDocumentUnits
        var changed = results
        for (id, r) in results where r.isOK {
            changed[id]?.estimatedSeconds = s.estimate(r.toolpaths, rapidRate: rapid, units: units)
        }
        if changed.contains(where: { results[$0.key]?.estimatedSeconds != $0.value.estimatedSeconds }) {
            results = changed
        }
    }
}
