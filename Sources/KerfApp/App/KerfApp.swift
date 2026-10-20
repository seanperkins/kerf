import AppKit
import SwiftUI

final class KerfAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct KerfApp: App {
    @NSApplicationDelegateAdaptor(KerfAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Kerf") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
