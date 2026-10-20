import AppKit
import SwiftUI

final class KerfAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        RecoveryCoordinator.shared.start()
        // Let the first windows open before asking about work left by a crash.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { RecoveryPrompt.offer(interactive: false) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        RecoveryCoordinator.shared.cleanUpOnQuit()
    }
}

@main
struct KerfApp: App {
    @NSApplicationDelegateAdaptor(KerfAppDelegate.self) private var appDelegate
    @StateObject private var toolLibrary = ToolLibraryModel.shared

    var body: some Scene {
        DocumentGroup(newDocument: { KerfDocument() }) { file in
            ContentView(document: file.document)
                .environmentObject(toolLibrary)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands { KerfCommands() }

        Window("Tool Database", id: ToolDatabaseView.windowID) {
            ToolDatabaseView()
                .environmentObject(toolLibrary)
        }
        .defaultSize(width: 820, height: 600)

        Settings {
            PreferencesView()
        }

        Window("Kerf Help", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 860, height: 600)
    }
}
