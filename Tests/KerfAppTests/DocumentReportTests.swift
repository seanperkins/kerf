import Foundation
import Testing
@testable import KerfApp

/// An alert cannot show over a sheet, so a report made while one is up waits for it to close.
@MainActor
@Suite struct DocumentReportTests {
    func document() -> KerfDocument {
        KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
    }

    @Test func aReportWithNoSheetShowsAtOnce() {
        let doc = document()
        doc.report(AlertMessage(title: "Done", message: "Two notes"))
        #expect(doc.alert?.title == "Done")
        #expect(doc.deferredAlert == nil)
    }

    @Test func aReportUnderASheetWaitsForTheSheetToClose() {
        let doc = document()
        doc.sheet = .jobSetup
        doc.report(AlertMessage(title: "Plates", message: "No column matched {Name}."))
        #expect(doc.alert == nil)
        doc.sheet = nil
        doc.sheetDismissed()
        #expect(doc.alert?.title == "Plates")
        #expect(doc.alert?.message == "No column matched {Name}.")
        #expect(doc.deferredAlert == nil)
    }

    @Test func reportsMadeUnderOneSheetAreJoinedNotLost() {
        let doc = document()
        doc.sheet = .jobSetup
        doc.report(AlertMessage(title: "First", message: "one"))
        doc.report(AlertMessage(title: "Second", message: "two"))
        doc.sheet = nil
        doc.sheetDismissed()
        #expect(doc.alert?.title == "First")
        #expect(doc.alert?.message == "one\n\nSecond: two")
    }

    @Test func anImportReportUnderASheetIsHeldNotDropped() {
        let doc = document()
        doc.sheet = .jobSetup
        doc.report(AlertMessage(title: "Plates", message: "Held first"))
        doc.importFiles([URL(fileURLWithPath: "/nonexistent/kerf-missing.dxf")])
        #expect(doc.alert == nil)
        doc.sheet = nil
        doc.sheetDismissed()
        #expect(doc.alert?.title == "Plates")
        #expect(doc.alert?.message.contains("Held first") == true)
        #expect(doc.alert?.message.contains("Import: kerf-missing.dxf") == true)
    }
}
