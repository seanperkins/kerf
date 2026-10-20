import AppKit
import SwiftUI
import Testing
@testable import KerfApp

/// Sheets hang from the document window, whose minimum is 1000 x 640 pt (`KerfApp`). A sheet taller than
/// that overhangs the window, and one with a scrolling form hides its last settings below the fold.
@Suite struct SheetSizeTests {
    static let minimumWindow = CGSize(width: 1000, height: 640)

    @Test @MainActor func jobSetupFitsTheMinimumWindow() {
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        let size = NSHostingView(rootView: JobSetupSheet(document: doc)).fittingSize
        #expect(size.width > 0)
        #expect(size.width <= Self.minimumWindow.width)
        #expect(size.height <= Self.minimumWindow.height)
    }
}
