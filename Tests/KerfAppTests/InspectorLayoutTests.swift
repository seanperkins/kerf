import AppKit
import CADCore
import Foundation
import SwiftUI
import Testing
@testable import KerfApp

/// The inspector sits under the window toolbar. A scroll view that takes the toolbar as a top content inset makes
/// SwiftUI report its controls' accessibility frames without that inset (52 pt above where they are drawn), so
/// a click or the VoiceOver cursor at the reported frame misses (issue #42). The inspector lays its content out
/// below the toolbar itself instead, so its scroll view has no top inset.
@MainActor
@Suite struct InspectorLayoutTests {
    func scrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { ($0 as? NSScrollView).map { [$0] } ?? [] + scrollViews(in: $0) }
    }

    @Test func theInspectorsScrollViewIsNotInsetByTheToolbar() throws {
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        let host = NSHostingView(rootView: InspectorView(document: doc).environmentObject(doc.toolLibrary))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "inspector-layout-test")
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        // The test only means something if the window really puts something above the content.
        #expect(host.safeAreaInsets.top > 0, Comment(rawValue: "safe area \(host.safeAreaInsets)"))
        let scroll = try #require(scrollViews(in: host).first)
        #expect(scroll.contentView.contentInsets.top == 0,
                Comment(rawValue: "the scroll view is inset by \(scroll.contentView.contentInsets.top) pt"))
        #expect(scroll.contentInsets.top == 0)
    }
}
