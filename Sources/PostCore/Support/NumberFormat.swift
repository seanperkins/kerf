import Foundation

/// Deterministic, locale-independent number formatting for G-code words.
enum NumberFormat {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Fixed `decimals` places; never emits "-0.000".
    static func fixed(_ value: Double, decimals: Int) -> String {
        let d = max(0, decimals)
        var s = String(format: "%.\(d)f", locale: posix, value)
        if s.hasPrefix("-"), s.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { s.removeFirst() }
        return s
    }

    /// Up to `maxDecimals` places with trailing zeros (and a trailing dot) removed: 3.000 -> "3".
    static func compact(_ value: Double, maxDecimals: Int = 3) -> String {
        var s = fixed(value, decimals: maxDecimals)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// "1h 02m 03s" style duration.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%dh %02dm %02ds", h, m, s) : String(format: "%dm %02ds", m, s)
    }
}
