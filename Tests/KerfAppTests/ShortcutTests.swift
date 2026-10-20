import Foundation
import Testing
@testable import KerfApp

/// Keyboard shortcuts, read from the source so a new binding cannot quietly clash.
@Suite struct ShortcutTests {
    /// Standard macOS shortcuts from the HIG "Keyboards" table that apps should not repurpose.
    static let reserved: Set<String> = ["⌥⌘T", "⌘I", "⌘[", "⌘]", "⌥⌘F", "⌘J"]
    /// Deliberate exceptions: Group / Ungroup use the drawing-app convention, and Kerf has no Find.
    static let allowedExceptions: Set<String> = ["⌘G", "⇧⌘G"]

    static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/KerfApp")
    }

    /// "⇧⌘I"-style names of every `.keyboardShortcut("x", modifiers: …)` with a literal key.
    static func bindings() throws -> [(name: String, file: String)] {
        let pattern = try NSRegularExpression(
            pattern: #"\.keyboardShortcut\(\s*"((?:\\.|[^"\\])+)"\s*(?:,\s*modifiers:\s*(\[[^\]]*\]|\.\w+))?\s*\)"#)
        var found: [(String, String)] = []
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for m in pattern.matches(in: text, range: range) {
                let key = String(text[Range(m.range(at: 1), in: text)!])
                let mods = m.range(at: 2).location == NSNotFound ? ".command" : String(text[Range(m.range(at: 2), in: text)!])
                var symbols = ""
                for (word, symbol) in [("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘")]
                where mods.contains(word) { symbols += symbol }
                found.append((symbols + key.uppercased(), url.lastPathComponent))
            }
        }
        return found
    }

    @Test func scannerFindsTheMenuShortcuts() throws {
        let names = try Self.bindings().map(\.name)
        #expect(names.count >= 20)
        #expect(names.contains("⌘P"))
        #expect(names.contains("⇧⌘J"))
    }

    @Test func noShortcutIsUsedTwice() throws {
        let names = try Self.bindings().map(\.name)
        let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "Used more than once: \(duplicates)")
    }

    @Test func noShortcutRepurposesAStandardOne() throws {
        let clashes = try Self.bindings().map(\.name).filter { Self.reserved.contains($0) }
        #expect(clashes.isEmpty, "Standard macOS shortcuts reused: \(clashes)")
        // The exceptions stay deliberate: if Group moves, this list should shrink too.
        #expect(Self.allowedExceptions.isDisjoint(with: Self.reserved))
    }

    @Test func helpListsTheCurrentBindings() throws {
        let text = HelpTopic.shortcuts.body
        for name in ["⇧⌘I", "⌥⌘P", "⌥⌘[", "⌥⌘]"] where try Self.bindings().map(\.name).contains(name) {
            #expect(text.contains(name), "Help does not mention \(name)")
        }
        #expect(!text.contains("⌥⌘T"))
    }
}
