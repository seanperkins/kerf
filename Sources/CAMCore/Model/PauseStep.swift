import Foundation

/// A stop for the operator after a toolpath: flip the part, add clamps or magnets, clear chips,
/// check the cut. The post lifts to safe Z, stops the spindle, shows the message and waits for the
/// controller's Cycle Start; the next toolpath then restarts the spindle.
public struct PauseStep: Codable, Hashable, Sendable {
    /// Shown on the controller. Empty = "Paused after <toolpath name>".
    public var message: String
    /// M1 instead of M0. The machine stops only when Optional Stop is switched on at the controller.
    public var isOptionalStop: Bool

    public init(message: String = "", isOptionalStop: Bool = false) {
        self.message = message; self.isOptionalStop = isOptionalStop
    }

    /// "M0" or "M1".
    public var stopCode: String { isOptionalStop ? "M1" : "M0" }

    /// The message to show for the toolpath that precedes the stop.
    public func text(afterToolpath name: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Paused after \(name)" : trimmed
    }
}
