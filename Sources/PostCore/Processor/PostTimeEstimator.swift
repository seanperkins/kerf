import CADCore
import CAMCore
import Foundation

/// Machining time estimate used for the G-code header. Feeds are assumed to be reached
/// instantly (no acceleration model), so real jobs run somewhat longer.
public enum PostTimeEstimator {
    /// Seconds to run `toolpaths` in order. Lengths/feeds in the same units; `rapidRate` in
    /// units per minute. `spindleDwell` is added for every spindle start (each tool / RPM change).
    public static func estimate(_ toolpaths: [Toolpath], rapidRate: Double,
                                spindleDwell: TimeInterval = 0) -> TimeInterval {
        var seconds: TimeInterval = 0
        var pos: Vec3?
        var lastToolID: UUID?
        var lastRPM: Double?
        for tp in toolpaths {
            if tp.tool.id != lastToolID || tp.spindleRPM != lastRPM { seconds += spindleDwell }
            lastToolID = tp.tool.id
            lastRPM = tp.spindleRPM
            for move in tp.moves {
                if case .dwell(let s) = move { seconds += max(0, s); continue }
                guard let target = move.target else { continue }
                defer { pos = target }
                guard let start = pos else { continue }
                let length: Double
                switch move {
                case .arcCW(_, let c, _): length = ArcGeometry.length(from: start, to: target, center: c, clockwise: true)
                case .arcCCW(_, let c, _): length = ArcGeometry.length(from: start, to: target, center: c, clockwise: false)
                default: length = start.distance(to: target)
                }
                let rate = move.isRapid ? rapidRate : (move.feed ?? 0)
                if rate > 0 { seconds += length / rate * 60 }
            }
        }
        return seconds
    }
}
