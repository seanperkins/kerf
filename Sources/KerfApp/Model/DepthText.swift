import CADCore
import Foundation

/// Wording for depths and heights shown next to the cutting numbers.
enum DepthText {
    /// A length to three decimals with trailing zeros dropped ("0.125", "-0.77", "19.05").
    static func number(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == 0 ? "0" : String(format: "%g", r)
    }
}
