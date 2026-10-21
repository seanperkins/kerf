import AppKit
import CADCore
import CAMCore
import Foundation
import SwiftUI
import Testing
@testable import KerfApp

/// Offscreen renders of the app-ux windows and the side-by-side view, to catch layout crashes.
@Suite struct AppUXRenderTests {
    @MainActor func render<V: View>(_ view: V, size: CGSize) -> Data? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    @Test func centerModes() {
        #expect(CenterMode.split.showsDesign && CenterMode.split.showsPreview)
        #expect(CenterMode.design2D.showsDesign && !CenterMode.design2D.showsPreview)
        #expect(!CenterMode.preview3D.showsDesign && CenterMode.preview3D.showsPreview)
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        doc.centerMode = .split
        doc.showDesignCanvas()
        #expect(doc.centerMode == .split)  // already visible: the split stays
        doc.centerMode = .preview3D
        doc.showDesignCanvas()
        #expect(doc.centerMode == .design2D)
    }

    @Test @MainActor func splitViewRenders() throws {
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        doc.centerMode = .split
        let data = try #require(render(ContentView(document: doc).environmentObject(doc.toolLibrary),
                                       size: CGSize(width: 1400, height: 800)))
        #expect(AppTestSupport.looksDrawn(data))
    }

    @Test @MainActor func utilityWindowsRender() throws {
        let suite = "kerf-tests-render-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let prefs = PreferencesModel(defaults: UserDefaults(suiteName: suite)!)
        #expect(AppTestSupport.looksDrawn(try #require(render(PreferencesView(model: prefs), size: CGSize(width: 640, height: 480)))))
        #expect(AppTestSupport.looksDrawn(try #require(render(HelpView(), size: CGSize(width: 860, height: 600)))))
        #expect(AppTestSupport.looksDrawn(try #require(render(WelcomeView(preferences: prefs), size: CGSize(width: 720, height: 520)))))
    }
}
