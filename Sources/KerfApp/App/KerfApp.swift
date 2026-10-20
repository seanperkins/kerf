import AppKit
import SwiftUI

final class KerfAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        .commands {
            KerfCommands()
            VectorMenuCommands()
        }

        Window("Tool Database", id: ToolDatabaseView.windowID) {
            ToolDatabaseView()
                .environmentObject(toolLibrary)
        }
        .defaultSize(width: 820, height: 600)
    }
}
