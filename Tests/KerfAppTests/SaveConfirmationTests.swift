import CADCore
import Foundation
import Testing
@testable import KerfApp

/// A save is only a save once the file holds the project. SwiftUI hands the bytes to the system after
/// `snapshot` and `fileWrapper`, and says nothing about the write, so the document counts the project as saved
/// (and the recovery copy as no longer needed) when it finds those exact bytes in the file.
@MainActor
@Suite struct SaveConfirmationTests {
    func makeDoc() -> KerfDocument {
        KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
    }

    /// A dirty document with a recovery copy written for it.
    func dirtyDocument(file url: URL, store: RecoveryStore) -> (KerfDocument, RecoveryCoordinator) {
        let doc = makeDoc()
        doc.fileURL = url
        let coordinator = RecoveryCoordinator(store: store)
        coordinator.register(doc)
        doc.perform("Rename") { $0.document.name = "Edited" }
        coordinator.tick()
        return (doc, coordinator)
    }

    func saveBytes(_ doc: KerfDocument) throws -> Data {
        let snap = try doc.snapshot(contentType: .kerfProject)
        return try doc.fileData(for: snap)
    }

    @Test func aSnapshotAloneDoesNotMarkTheProjectSaved() throws {
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        let (doc, coordinator) = dirtyDocument(file: AppTestSupport.tempDir().appendingPathComponent("a.kerf"), store: store)
        #expect(store.entries().count == 1)
        _ = try saveBytes(doc)
        #expect(doc.needsRecovery)
        coordinator.tick()
        #expect(store.entries().count == 1)
    }

    @Test func aFailedWriteKeepsTheDocumentDirtyAndItsRecoveryCopy() throws {
        let folder = AppTestSupport.tempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let url = folder.appendingPathComponent("locked.kerf")
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        let (doc, coordinator) = dirtyDocument(file: url, store: store)

        let data = try saveBytes(doc)
        #expect(throws: (any Error).self) { try data.write(to: url) }   // the system's write fails
        #expect(!doc.confirmSave())
        #expect(doc.needsRecovery)
        coordinator.tick()
        #expect(store.entries().map(\.name) == ["Edited"])
    }

    @Test func aSuccessfulWriteClearsBothTheDirtyStateAndTheRecoveryCopy() throws {
        let url = AppTestSupport.tempDir().appendingPathComponent("ok.kerf")
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        let (doc, coordinator) = dirtyDocument(file: url, store: store)
        #expect(store.entries().count == 1)

        try saveBytes(doc).write(to: url)
        #expect(doc.confirmSave())
        #expect(!doc.needsRecovery)
        coordinator.tick()
        #expect(store.entries().isEmpty)
    }

    @Test func theRecoveryTimerConfirmsASaveItWasNotToldAbout() throws {
        let url = AppTestSupport.tempDir().appendingPathComponent("tick.kerf")
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        let (doc, coordinator) = dirtyDocument(file: url, store: store)
        try saveBytes(doc).write(to: url)
        coordinator.tick()
        #expect(!doc.needsRecovery)
        #expect(store.entries().isEmpty)
    }

    @Test func aFileThatHoldsSomethingElseIsNotAConfirmation() throws {
        let url = AppTestSupport.tempDir().appendingPathComponent("other.kerf")
        let doc = makeDoc()
        doc.fileURL = url
        doc.perform("Rename") { $0.document.name = "Edited" }
        _ = try saveBytes(doc)
        try Data("the previous version".utf8).write(to: url)   // the write did not replace it
        #expect(!doc.confirmSave())
        #expect(doc.needsRecovery)
        // And with no file at all, or a document that was never given a place.
        try FileManager.default.removeItem(at: url)
        #expect(!doc.confirmSave())
        doc.fileURL = nil
        #expect(!doc.confirmSave())
    }

    @Test func editsMadeAfterTheSaveStayUnsaved() throws {
        let url = AppTestSupport.tempDir().appendingPathComponent("later.kerf")
        let doc = makeDoc()
        doc.fileURL = url
        doc.perform("First") { $0.document.name = "First" }
        try saveBytes(doc).write(to: url)
        doc.perform("Second") { $0.document.name = "Second" }
        #expect(doc.confirmSave())
        #expect(doc.lastSavedProject.document.name == "First")
        #expect(doc.needsRecovery)   // the second edit is not in the file
    }

    @Test func aLaterFailedSaveDoesNotUndoAnEarlierConfirmedOne() throws {
        let url = AppTestSupport.tempDir().appendingPathComponent("twice.kerf")
        let doc = makeDoc()
        doc.fileURL = url
        doc.perform("First") { $0.document.name = "First" }
        try saveBytes(doc).write(to: url)
        #expect(doc.confirmSave())
        doc.perform("Second") { $0.document.name = "Second" }
        _ = try saveBytes(doc)                 // handed over, never written
        #expect(!doc.confirmSave())
        #expect(doc.lastSavedProject.document.name == "First")
        #expect(doc.needsRecovery)
        // Confirming when nothing is pending, or twice, changes nothing.
        try saveBytes(doc).write(to: url)
        #expect(doc.confirmSave())
        #expect(!doc.confirmSave())
        #expect(!doc.needsRecovery)
    }
}
