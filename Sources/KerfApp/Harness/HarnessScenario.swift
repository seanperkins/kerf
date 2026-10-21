#if DEBUG
import Foundation

struct HarnessError: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
}

/// A scripted run of the UI harness: an appearance, a window size and a list of steps, ending in
/// `capture` steps that write PNGs and text dumps. Debug builds only. See `UIHarness` and
/// `docs/UI-HARNESS.md`.
struct HarnessScenario: Decodable {
    struct Step: Decodable {
        var op: String
        /// A file stem (capture, captureSheet, menus), a sample name, or a shape / toolpath name.
        var name: String?
        /// An enumerated value: a mode, tab, sheet, tool or appearance.
        var value: String?
        /// Shape names to select.
        var names: [String]?
        /// Width and height in points.
        var size: [Double]?
        var seconds: Double?
    }

    var name: String?
    /// "light", "dark" or "system" (the default).
    var appearance: String?
    /// Content size of the document window, in points.
    var window: [Double]?
    var steps: [Step]

    static let modes: Set<String> = ["2d", "split", "3d"]
    static let tabs: Set<String> = ["design", "toolpaths"]
    static let appearances: Set<String> = ["light", "dark", "system"]
    static let samples: Set<String> = ["sign"]
    static let keys: [String: (code: UInt16, chars: String)] = [
        "escape": (53, "\u{1b}"), "return": (36, "\r"), "tab": (48, "\t"), "space": (49, " "),
    ]
    static let sheets: Set<String> = [
        "jobSetup", "exportGCode", "saveAllToolpaths", "validation", "keepOutZones", "nesting", "fixtures",
        "tiling", "partLabels", "variables", "productionPlates", "offset", "joinVectors", "inlayWizard",
    ]

    /// Each op and what it needs; `capture` and friends write `<name>.png` and `<name>.ax.txt`.
    static let ops: [String: String] = [
        "sample": "name: load a sample project (sign)",
        "project": "name: load a .kerf project file, relative to the repo root (scripts/ui.sh runs from there); harness/projects/ holds variants of the sample",
        "appearance": "value: light | dark | system",
        "size": "size: [w, h] content size of the window",
        "mode": "value: 2d | split | 3d",
        "tab": "value: design | toolpaths",
        "tool": "value: a canvas tool such as select, rectangle, nodeEdit",
        "select": "names: shapes to select by name",
        "selectToolpath": "name: a toolpath to select (also shows the Toolpaths tab)",
        "calculate": "calculate all toolpaths and wait",
        "sheet": "value: " + sheets.sorted().joined(separator: " | "),
        "closeSheet": "close the open sheet or alert",
        "import": "name: a file to import as File > Import does, relative to the repo root (scripts/ui.sh runs from there). An import alert stays open until a closeSheet step",
        "press": "name: click the first control whose label, title, help or id contains this text; value: optional role such as AXButton. Does not toggle disclosure groups: use expand",
        "key": "value: escape | return | tab | space, sent to the open sheet (or the window)",
        "expand": "name: open a collapsible inspector section by its title (Last Pass, Ramps, Array Copies...)",
        "wait": "seconds: let the UI settle",
        "capture": "name: the window as <name>.png, its accessibility tree as <name>.ax.txt",
        "captureSheet": "name: the open sheet as <name>.png and <name>.ax.txt",
        "menus": "name: the menu bar (titles, enabled state, key equivalents) as <name>.menus.txt",
    ]

    static func parse(_ data: Data) throws -> HarnessScenario {
        let scenario: HarnessScenario
        do { scenario = try JSONDecoder().decode(HarnessScenario.self, from: data) } catch {
            throw HarnessError(message: "The scenario is not valid JSON of the expected shape: \(error)")
        }
        if let a = scenario.appearance, !appearances.contains(a) {
            throw HarnessError(message: "appearance must be light, dark or system, not \"\(a)\"")
        }
        if let w = scenario.window, w.count != 2 || w.contains(where: { $0 <= 0 }) {
            throw HarnessError(message: "window must be [width, height] in points")
        }
        for (i, step) in scenario.steps.enumerated() {
            try validate(step, at: i + 1)
        }
        return scenario
    }

    private static func validate(_ step: Step, at n: Int) throws {
        func fail(_ text: String) -> HarnessError { HarnessError(message: "step \(n) (\(step.op)): \(text)") }
        guard ops[step.op] != nil else {
            throw HarnessError(message: "step \(n): unknown op \"\(step.op)\". Valid ops: " + ops.keys.sorted().joined(separator: ", "))
        }
        switch step.op {
        case "sample":
            guard let n = step.name, samples.contains(n) else { throw fail("name must be one of \(samples.sorted())") }
        case "appearance":
            guard let v = step.value, appearances.contains(v) else { throw fail("value must be light, dark or system") }
        case "size":
            guard let s = step.size, s.count == 2, s.allSatisfy({ $0 > 0 }) else { throw fail("size must be [width, height]") }
        case "mode":
            guard let v = step.value, modes.contains(v) else { throw fail("value must be 2d, split or 3d") }
        case "tab":
            guard let v = step.value, tabs.contains(v) else { throw fail("value must be design or toolpaths") }
        case "tool":
            guard step.value?.isEmpty == false else { throw fail("value must name a tool") }
        case "select":
            guard let names = step.names, !names.isEmpty else { throw fail("names must list the shapes to select") }
        case "selectToolpath":
            guard step.name?.isEmpty == false else { throw fail("name must name a toolpath") }
        case "sheet":
            guard let v = step.value, sheets.contains(v) else { throw fail("value must be one of \(sheets.sorted())") }
        case "press":
            guard step.name?.isEmpty == false else { throw fail("name must say which control to press") }
        case "key":
            guard let v = step.value, keys[v] != nil else { throw fail("value must be one of \(keys.keys.sorted())") }
        case "expand":
            guard step.name?.isEmpty == false else { throw fail("name must be the section's title") }
        case "import":
            guard step.name?.isEmpty == false else { throw fail("name must be the path of the file to import") }
        case "project":
            guard step.name?.isEmpty == false else { throw fail("name must be the path of a .kerf file") }
        case "wait":
            guard let s = step.seconds, s >= 0 else { throw fail("seconds is required") }
        case "capture", "captureSheet", "menus":
            guard step.name?.isEmpty == false else { throw fail("name is required (the output file name)") }
        default:
            break
        }
    }

    /// A name made safe to use as a file name inside the output folder.
    static func fileStem(_ name: String) -> String {
        let pieces = name.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") }).map(String.init)
        let stem = pieces.joined(separator: "-")
        return stem.isEmpty ? "capture" : stem
    }
}
#endif
