import Foundation

/// Tokeniser for SVG number lists, path data and transform lists. Handles the compact forms
/// SVG allows ("1.5.5" = 1.5, .5; "1-2" = 1, -2; "1e-3") and arc flags written without
/// separators ("a1 1 0 01 1 1").
struct SVGNumberScanner {
    private let bytes: [UInt8]
    private(set) var index = 0

    init(_ s: Substring) { bytes = Array(s.utf8) }
    init(_ s: String) { bytes = Array(s.utf8) }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func skipSeparators() {
        while index < bytes.count, Self.isSeparator(bytes[index]) { index += 1 }
    }

    /// Next non-separator byte without consuming it.
    mutating func peek() -> UInt8? {
        skipSeparators()
        return isAtEnd ? nil : bytes[index]
    }

    mutating func advance() { index += 1 }

    /// True if the next token starts a number.
    mutating func hasNumber() -> Bool {
        guard let c = peek() else { return false }
        return Self.isDigit(c) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
    }

    mutating func number() -> Double? {
        skipSeparators()
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
        var sawDigit = false, sawDot = false
        while index < bytes.count {
            let c = bytes[index]
            if Self.isDigit(c) { sawDigit = true; index += 1 }
            else if c == UInt8(ascii: "."), !sawDot { sawDot = true; index += 1 }
            else { break }
        }
        guard sawDigit else { index = start; return nil }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            var j = index + 1
            if j < bytes.count, bytes[j] == UInt8(ascii: "-") || bytes[j] == UInt8(ascii: "+") { j += 1 }
            if j < bytes.count, Self.isDigit(bytes[j]) {
                while j < bytes.count, Self.isDigit(bytes[j]) { j += 1 }
                index = j
            }
        }
        return Double(String(decoding: bytes[start..<index], as: UTF8.self))
    }

    /// Arc flag: a single '0' or '1' (may be immediately followed by the next number).
    mutating func flag() -> Bool? {
        guard let c = peek() else { return nil }
        if c == UInt8(ascii: "0") { index += 1; return false }
        if c == UInt8(ascii: "1") { index += 1; return true }
        return nil
    }

    /// Identifier made of letters (e.g. "matrix", "translate").
    mutating func identifier() -> String? {
        skipSeparators()
        let start = index
        while index < bytes.count, Self.isLetter(bytes[index]) || bytes[index] == UInt8(ascii: "-") { index += 1 }
        return index > start ? String(decoding: bytes[start..<index], as: UTF8.self) : nil
    }

    /// Consume `c` if it is the next non-separator byte.
    mutating func consume(_ c: Character) -> Bool {
        if peek() == c.asciiValue { index += 1; return true }
        return false
    }

    /// All numbers in the string (used for `points`, `viewBox`).
    static func numbers(in s: String) -> [Double] {
        var sc = SVGNumberScanner(s)
        var out: [Double] = []
        while !sc.isAtEnd {
            if let n = sc.number() { out.append(n) } else { sc.skipSeparators(); if !sc.isAtEnd { sc.advance() } }
        }
        return out
    }

    static func isSeparator(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == UInt8(ascii: ",")
    }
    static func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
    static func isLetter(_ c: UInt8) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
}
