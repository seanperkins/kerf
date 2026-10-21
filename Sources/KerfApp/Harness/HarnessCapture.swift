#if DEBUG
import AppKit
import ApplicationServices
import SceneKit

/// Screenshots and text dumps of the app's own windows, taken from inside the process: no Screen
/// Recording or Accessibility permission, and the window does not have to be on screen or in front.
@MainActor
enum HarnessCapture {
    /// The window as drawn, title bar and toolbar included, at the display's scale.
    static func png(of window: NSWindow, scale: CGFloat = 2) -> Data? {
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        // An explicit 2x bitmap: a window that is not on a display would otherwise be drawn at 1x.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        // SceneKit draws with Metal and comes out blank in cacheDisplay: paste in its own snapshot.
        for scn in descendants(of: frameView).compactMap({ $0 as? SCNView }) where !scn.isHidden {
            var r = frameView.convert(scn.bounds, from: scn)
            if frameView.isFlipped { r.origin.y = bounds.height - r.maxY }
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                scn.snapshot().draw(in: r)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep.representation(using: .png, properties: [:])
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    // MARK: Accessibility tree

    /// The accessibility tree of `window` as VoiceOver sees it. SwiftUI only builds its accessibility
    /// nodes for an attached client, so this reads the app's own tree through the Accessibility API
    /// (from a background thread: the main thread has to stay free to answer). That needs the parent
    /// process (your terminal) to be trusted for Accessibility; without it, the sparse in-process view of
    /// the window chrome is returned with a note saying so.
    static func accessibilityTree(of window: NSWindow) async -> String {
        guard AXIsProcessTrusted() else {
            return "# Accessibility is not granted to this process's parent, so only the window chrome is listed.\n"
                + "# Grant Accessibility to your terminal (System Settings > Privacy & Security) for the full tree.\n"
                + accessibilityChrome(of: window)
        }
        let frame = window.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: axTree(windowFrame: frame, screenHeight: screenHeight))
            }
        }
    }

    /// Presses the first control under `window` whose title, description, help or identifier contains `text`:
    /// the Accessibility API finds it, then a real mouse click is delivered into the window in-process (AX
    /// actions on the app's own controls fail with "cannot complete"). Returns what was pressed, or nil.
    static func press(text: String, role: String?, in window: NSWindow) async -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let frame = window.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let found: (name: String, center: CGPoint)? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: axLocate(text: text, role: role, windowFrame: frame, screenHeight: screenHeight))
            }
        }
        guard let found else { return nil }
        click(at: found.center, in: window)
        return found.name
    }

    /// A left click at `point` (window coordinates, origin bottom left).
    private static func click(at point: CGPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { continue }
            window.sendEvent(event)
        }
    }

    private nonisolated static func axLocate(text: String, role: String?, windowFrame: NSRect,
                                             screenHeight: CGFloat) -> (name: String, center: CGPoint)? {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 5)
        func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
        }
        func str(_ e: AXUIElement, _ name: String) -> String { (attr(e, name) as? String) ?? "" }
        func rect(_ e: AXUIElement) -> CGRect? {
            var p = CGPoint.zero, s = CGSize.zero
            guard let pv = attr(e, kAXPositionAttribute), CFGetTypeID(pv) == AXValueGetTypeID(),
                  let sv = attr(e, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
            AXValueGetValue(pv as! AXValue, .cgPoint, &p)
            AXValueGetValue(sv as! AXValue, .cgSize, &s)
            return CGRect(origin: p, size: s)
        }
        let top = screenHeight - windowFrame.maxY
        let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let root = windows.first(where: {
            guard let r = rect($0) else { return false }
            return abs(r.minX - windowFrame.minX) < 2 && abs(r.minY - top) < 2
        }) ?? windows.first else { return nil }
        let needle = text.lowercased()
        var hit: AXUIElement?
        func visit(_ e: AXUIElement, depth: Int) {
            guard hit == nil, depth < 40 else { return }
            let matches = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXIdentifier"]
                .contains { str(e, $0).lowercased().contains(needle) }
            if matches, role == nil || str(e, kAXRoleAttribute) == role, str(e, kAXEnabledAttribute) != "0", let r = rect(e), r.width > 0 {
                hit = e
                return
            }
            for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        guard let hit, let r = rect(hit) else { print("[harness] press: nothing matched \"\(text)\""); return nil }
        // Screen top-left origin to window bottom-left origin.
        let center = CGPoint(x: r.midX - windowFrame.minX, y: (screenHeight - r.midY) - windowFrame.minY)
        let name = [str(hit, kAXTitleAttribute), str(hit, kAXDescriptionAttribute)].first { !$0.isEmpty } ?? str(hit, "AXIdentifier")
        return ("\(str(hit, kAXRoleAttribute)) \"\(name)\"", center)
    }

    private nonisolated static func axTree(windowFrame: NSRect, screenHeight: CGFloat) -> String {
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 5)
        func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
            var v: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
        }
        func text(_ e: AXUIElement, _ name: String) -> String {
            guard let v = attr(e, name) else { return "" }
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return ""
        }
        func frame(_ e: AXUIElement) -> CGRect? {
            var p = CGPoint.zero, s = CGSize.zero
            guard let pv = attr(e, kAXPositionAttribute), CFGetTypeID(pv) == AXValueGetTypeID(),
                  let sv = attr(e, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
            AXValueGetValue(pv as! AXValue, .cgPoint, &p)
            AXValueGetValue(sv as! AXValue, .cgSize, &s)
            return CGRect(origin: p, size: s)
        }
        // AX frames are in screen points with the origin at the top left; NSWindow's are bottom left.
        let top = screenHeight - windowFrame.maxY
        let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        guard let root = windows.first(where: {
            guard let f = frame($0) else { return false }
            return abs(f.minX - windowFrame.minX) < 2 && abs(f.minY - top) < 2 && abs(f.width - windowFrame.width) < 2
        }) ?? windows.first else { return "# no accessibility window found\n" }
        let origin = frame(root)?.origin ?? .zero

        var lines: [String] = []
        func visit(_ e: AXUIElement, depth: Int) {
            guard lines.count < 6000 else { return }
            var line = String(repeating: "  ", count: depth) + text(e, kAXRoleAttribute)
            let sub = text(e, kAXSubroleAttribute)
            if !sub.isEmpty { line += "/" + sub }
            for (label, key) in [("title", kAXTitleAttribute), ("desc", kAXDescriptionAttribute), ("help", kAXHelpAttribute),
                                 ("value", kAXValueAttribute), ("id", "AXIdentifier")] {
                let v = text(e, key)
                if !v.isEmpty { line += " \(label)=\"\(v.prefix(90))\"" }
            }
            if text(e, kAXEnabledAttribute) == "0" { line += " DISABLED" }
            if let f = frame(e) {
                line += "  [\(Int(f.minX - origin.x)),\(Int(f.minY - origin.y)) \(Int(f.width))x\(Int(f.height))]"
            }
            lines.append(line)
            for child in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return lines.joined(separator: "\n") + "\n"
    }

    /// The accessibility tree under `window`, one element per line: role, label, value, help and the
    /// frame in window points (origin top left). This is what VoiceOver sees.
    private static func accessibilityChrome(of window: NSWindow) -> String {
        var lines: [String] = []
        let origin = window.frame
        func visit(_ object: Any, depth: Int) {
            guard lines.count < 6000 else { return }
            let element = object as AnyObject
            let a = element as? NSAccessibilityProtocol
            let role = a?.accessibilityRole()?.rawValue ?? String(describing: type(of: element))
            var line = String(repeating: "  ", count: depth) + role
            if let sub = a?.accessibilitySubrole()?.rawValue { line += "/" + sub }
            if let label = a?.accessibilityLabel(), !label.isEmpty { line += " label=\"\(label.prefix(90))\"" }
            if let title = a?.accessibilityTitle(), !title.isEmpty { line += " title=\"\(title.prefix(90))\"" }
            if let value = a?.accessibilityValue() {
                let text = "\(value)"
                if !text.isEmpty { line += " value=\"\(text.prefix(90))\"" }
            }
            if let help = a?.accessibilityHelp(), !help.isEmpty { line += " help=\"\(help.prefix(70))\"" }
            if a?.isAccessibilityEnabled() == false { line += " DISABLED" }
            if let f = a?.accessibilityFrame(), f.width > 0 || f.height > 0 {
                let x = Int(f.minX - origin.minX), y = Int(origin.maxY - f.maxY)
                line += "  [\(x),\(y) \(Int(f.width))x\(Int(f.height))]"
            }
            lines.append(line)
            for child in a?.accessibilityChildren() ?? [] { visit(child, depth: depth + 1) }
        }
        visit(window, depth: 0)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Menus

    /// The menu bar: titles, enabled state and key equivalents, as validated for the current focus.
    static func menuDump() -> String {
        guard let main = NSApp.mainMenu else { return "(no main menu)\n" }
        var lines: [String] = []
        func visit(_ menu: NSMenu, depth: Int) {
            menu.update()
            for item in menu.items {
                let pad = String(repeating: "  ", count: depth)
                if item.isSeparatorItem { lines.append(pad + "---"); continue }
                var line = pad + item.title
                if !item.isEnabled { line += "  (disabled)" }
                let key = keyText(item)
                if !key.isEmpty { line += "  \(key)" }
                if item.state == .on { line += "  ✓" }
                lines.append(line)
                if let sub = item.submenu { visit(sub, depth: depth + 1) }
            }
        }
        for item in main.items {
            lines.append("[\(item.title)]")
            if let sub = item.submenu { visit(sub, depth: 1) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func keyText(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let m = item.keyEquivalentModifierMask
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s + item.keyEquivalent.uppercased()
    }
}
#endif
