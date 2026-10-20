#if DEBUG
import AppKit
import CADCore
import CAMCore
import SwiftUI

/// A scripted, headless-friendly UI driver for debug builds.
///
///     Kerf --ui-scenario harness/scenarios/profile.json --ui-out .tmp/ui/run [--ui-active 1]
///
/// Every flag takes a value: AppKit reads `-key value` pairs from the arguments, and a bare flag shifts the
/// pairing so the next value ("YES") is taken for a file to open.
///
/// It opens an untitled document, runs the scenario's steps against the live app, writes PNGs and text
/// dumps (accessibility tree, menus) taken from inside the process, then exits. Nothing needs Screen
/// Recording or Accessibility permission, the window does not need to be on screen, and `scripts/ui.sh`
/// gives the run its own HOME so it never touches real preferences, tools or recovery files.
/// See `docs/UI-HARNESS.md`.
@MainActor
final class UIHarness {
    static let shared = UIHarness()

    struct Request {
        var scenario: URL
        var out: URL
        /// Make the app active, so the window is drawn as the key window (coloured traffic lights and selection).
        var active: Bool
        /// Overrides of the scenario's appearance ("light", "dark") and window size, from the command line.
        var appearance: String?
        var size: [Double]?
    }

    static var request: Request? {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let scenario = value(after: "--ui-scenario") else { return nil }
        let out = value(after: "--ui-out") ?? ".tmp/ui/run"
        let size = value(after: "--ui-size").map { $0.split(separator: "x").compactMap { Double($0) } }
        return Request(scenario: URL(fileURLWithPath: scenario), out: URL(fileURLWithPath: out, isDirectory: true),
                       active: value(after: "--ui-active") == "1", appearance: value(after: "--ui-appearance"),
                       size: size?.count == 2 ? size : nil)
    }

    static var isActive: Bool { request != nil }

    private weak var document: KerfDocument?
    private var log: [String] = []
    private var outDir = URL(fileURLWithPath: ".")

    /// Called when a document window appears.
    func noteDocument(_ doc: KerfDocument) { if document == nil { document = doc } }

    func start() {
        guard let request = Self.request else { return }
        outDir = request.out
        // Never hang a run, even if the main thread is blocked: this watchdog is on its own thread.
        let log = outDir.appendingPathComponent("harness.log")
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
            try? "timed out after 90 s (the main thread may be blocked)\n".write(to: log, atomically: true, encoding: .utf8)
            print("[harness] finished: timed out after 90 s")
            _exit(2)
        }
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                let scenario = try HarnessScenario.parse(Data(contentsOf: request.scenario))
                try await run(scenario, request: request)
                finish("ok", code: 0)
            } catch {
                finish("\(error)", code: 1)
            }
        }
    }

    private func say(_ text: String) {
        log.append(text)
        print("[harness] \(text)")
        fflush(stdout)
    }

    private func finish(_ status: String, code: Int32) {
        say("finished: \(status)")
        try? (log.joined(separator: "\n") + "\n").write(to: outDir.appendingPathComponent("harness.log"), atomically: true, encoding: .utf8)
        exit(code)
    }

    // MARK: Running

    private func run(_ scenario: HarnessScenario, request: Request) async throws {
        apply(appearance: request.appearance ?? scenario.appearance ?? "system")
        if document == nil { NSDocumentController.shared.newDocument(nil) }
        try await waitUntil("a document window") { self.document != nil && self.window != nil }
        let window = try requireWindow()
        if let s = request.size ?? scenario.window { window.setContentSize(NSSize(width: s[0], height: s[1])) }
        if request.active {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        await settle()
        say("window \(Int(window.frame.width))x\(Int(window.frame.height)) at \(Int(window.frame.minX)),\(Int(window.frame.minY)); "
            + "appearance \(window.effectiveAppearance.name.rawValue)")
        for (i, step) in scenario.steps.enumerated() {
            say("step \(i + 1): \(step.op)")
            try await perform(step)
        }
    }

    private var window: NSWindow? {
        NSDocumentController.shared.documents.compactMap { $0.windowControllers.first?.window }.first { $0.isVisible || $0.contentView != nil }
    }

    private func requireWindow() throws -> NSWindow {
        guard let w = window else { throw HarnessError(message: "no document window") }
        return w
    }

    private func requireDocument() throws -> KerfDocument {
        guard let d = document else { throw HarnessError(message: "no document") }
        return d
    }

    private func apply(appearance: String) {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private func perform(_ step: HarnessScenario.Step) async throws {
        let doc = try requireDocument()
        switch step.op {
        case "sample":
            guard let url = SampleProjects.url(for: SampleProjects.sign) else { throw HarnessError(message: "the sample sign was not found") }
            let project = try KerfProject.decode(from: Data(contentsOf: url))
            doc.perform("Load sample") { $0 = project }
            doc.setSelection([])
            doc.requestCanvas(.fit)
            await settle()
        case "project":
            let path = step.name ?? ""
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { throw HarnessError(message: "project: no file at \(url.path)") }
            let project = try KerfProject.decode(from: Data(contentsOf: url))
            doc.perform("Load project") { $0 = project }
            doc.setSelection([])
            doc.requestCanvas(.fit)
            await settle()
        case "appearance":
            apply(appearance: step.value ?? "system")
            await settle()
        case "size":
            let s = step.size ?? [1000, 640]
            try requireWindow().setContentSize(NSSize(width: s[0], height: s[1]))
            await settle()
        case "mode":
            doc.centerMode = ["2d": CenterMode.design2D, "split": .split, "3d": .preview3D][step.value ?? ""] ?? .design2D
            await settle()
        case "tab":
            doc.sidebarTab = step.value == "toolpaths" ? .toolpaths : .design
            await settle()
        case "tool":
            guard let tool = CanvasTool(rawValue: step.value ?? "") else {
                throw HarnessError(message: "unknown tool \"\(step.value ?? "")\"; tools: " + CanvasTool.allCases.map(\.rawValue).joined(separator: ", "))
            }
            doc.activeTool = tool
            await settle()
        case "select":
            let wanted = Set(step.names ?? [])
            let ids = doc.project.document.shapes.filter { wanted.contains($0.name) }.map(\.id)
            guard !ids.isEmpty else {
                throw HarnessError(message: "no shape named \(wanted.sorted()); shapes: "
                    + Set(doc.project.document.shapes.map(\.name)).sorted().joined(separator: ", "))
            }
            doc.setSelection(ids)
            await settle()
        case "selectToolpath":
            guard let op = doc.project.operations.first(where: { $0.setup.name == step.name }) else {
                throw HarnessError(message: "no toolpath named \"\(step.name ?? "")\"; toolpaths: "
                    + doc.project.operations.map(\.setup.name).joined(separator: ", "))
            }
            doc.sidebarTab = .toolpaths
            doc.selectedOperationID = op.id
            await settle()
        case "calculate":
            doc.calculateAll()
            try await waitUntil("toolpaths to calculate", timeout: 40) {
                doc.calculating.isEmpty && !doc.results.isEmpty
            }
            await settle(0.8)
        case "sheet":
            doc.sheet = try sheet(named: step.value ?? "")
            try await waitUntil("a sheet") { self.window?.attachedSheet != nil }
            await settle(0.9)
        case "closeSheet":
            doc.sheet = nil
            doc.alert = nil
            await settle(0.7)
        case "import":
            let path = step.name ?? ""
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { throw HarnessError(message: "import: no file at \(url.path)") }
            doc.importFiles([url])
            await settle(0.9)
        case "key":
            guard let key = HarnessScenario.keys[step.value ?? ""] else { throw HarnessError(message: "unknown key") }
            let target = try requireWindow().attachedSheet ?? requireWindow()
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: target.windowNumber, context: nil, characters: key.chars,
                                                   charactersIgnoringModifiers: key.chars, isARepeat: false,
                                                   keyCode: key.code) else { continue }
                target.sendEvent(event)
            }
            await settle(0.7)
        case "expand":
            UserDefaults.standard.set(true, forKey: SectionState.key(for: step.name ?? ""))
            await settle()
        case "press":
            let win = try requireWindow().attachedSheet ?? requireWindow()
            guard let pressed = await HarnessCapture.press(text: step.name ?? "", role: step.value, in: win) else {
                throw HarnessError(message: "no control matching \"\(step.name ?? "")\" could be pressed (Accessibility must be granted to your terminal)")
            }
            say("pressed \(pressed)")
            await settle(0.6)
        case "wait":
            await settle(step.seconds ?? 0.5)
        case "capture":
            try await write(window: try requireWindow(), stem: step.name ?? "capture")
        case "captureSheet":
            guard let sheet = try requireWindow().attachedSheet else { throw HarnessError(message: "no sheet is open") }
            try await write(window: sheet, stem: step.name ?? "sheet")
        case "menus":
            let stem = HarnessScenario.fileStem(step.name ?? "menus")
            try HarnessCapture.menuDump().write(to: outDir.appendingPathComponent(stem + ".menus.txt"), atomically: true, encoding: .utf8)
            say("wrote \(stem).menus.txt")
        default:
            throw HarnessError(message: "unhandled op \(step.op)")
        }
    }

    private func sheet(named name: String) throws -> DocumentSheet {
        switch name {
        case "jobSetup": return .jobSetup
        case "exportGCode": return .exportGCode(.all)
        case "saveAllToolpaths": return .saveAllToolpaths
        case "validation": return .validation
        case "keepOutZones": return .keepOutZones
        case "nesting": return .nesting
        case "fixtures": return .fixtures
        case "tiling": return .tiling
        case "partLabels": return .partLabels
        case "variables": return .variables
        case "productionPlates": return .productionPlates
        case "offset": return .offset
        case "joinVectors": return .drawing(.joinVectors)
        case "inlayWizard": return .inlayWizard
        default: throw HarnessError(message: "unknown sheet \"\(name)\"")
        }
    }

    private func write(window: NSWindow, stem rawStem: String) async throws {
        let stem = HarnessScenario.fileStem(rawStem)
        guard let png = HarnessCapture.png(of: window) else { throw HarnessError(message: "could not capture the window") }
        try png.write(to: outDir.appendingPathComponent(stem + ".png"))
        try await HarnessCapture.accessibilityTree(of: window)
            .write(to: outDir.appendingPathComponent(stem + ".ax.txt"), atomically: true, encoding: .utf8)
        say("wrote \(stem).png (\(Int(window.frame.width))x\(Int(window.frame.height)) pt) and \(stem).ax.txt")
    }

    // MARK: Waiting

    /// Lets SwiftUI lay out and the run loop drain.
    private func settle(_ seconds: Double = 0.45) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func waitUntil(_ what: String, timeout: Double = 15, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw HarnessError(message: "timed out waiting for \(what)") }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
#endif
