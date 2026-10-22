import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct RecoveryTests {
    func makeDoc() -> KerfDocument {
        KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
    }

    @Test func storeWritesListsAndRemoves() throws {
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        #expect(store.entries().isEmpty)
        let a = RecoveryEntry(id: UUID(), name: "Old", savedAt: Date(timeIntervalSince1970: 1000))
        let b = RecoveryEntry(id: UUID(), name: "New", savedAt: Date(timeIntervalSince1970: 2000))
        let project = AppTestSupport.project()
        try store.write(project, entry: a)
        try store.write(KerfProject(), entry: b)
        #expect(store.entries().map(\.name) == ["New", "Old"])
        #expect(try store.project(for: a.id) == project)
        store.remove(a.id)
        #expect(store.entries().map(\.id) == [b.id])
    }

    @Test func archiveMovesAndPrunes() throws {
        var store = RecoveryStore(directory: AppTestSupport.tempDir())
        store.archiveLimit = 2
        var ids: [UUID] = []
        for i in 0..<3 {
            let e = RecoveryEntry(id: UUID(), name: "D\(i)", savedAt: Date())
            try store.write(KerfProject(), entry: e)
            ids.append(e.id)
            store.archive(e.id)
        }
        #expect(store.entries().isEmpty)
        #expect(store.archivedProjects().count == 2)
    }

    @Test func coordinatorWritesOnlyDirtyDocuments() throws {
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        let c = RecoveryCoordinator(store: store)
        let doc = makeDoc()
        c.register(doc)
        c.tick()
        #expect(store.entries().isEmpty)  // nothing changed since open

        doc.perform("Rename") { $0.document.name = "Edited" }
        c.tick()
        #expect(store.entries().map(\.name) == ["Edited"])
        #expect(try store.project(for: doc.recoveryID) == doc.project)

        // A save that reached the file makes it clean again: the copy is removed on the next tick.
        let url = AppTestSupport.tempDir().appendingPathComponent("saved.kerf")
        doc.fileURL = url
        let snap = try doc.snapshot(contentType: .kerfProject)
        try doc.fileData(for: snap).write(to: url)
        c.tick()                                  // looks at the file
        #expect(!doc.needsRecovery)
        #expect(store.entries().isEmpty)
    }

    @Test func closingWindowOrQuittingRemovesOwnCopiesOnly() throws {
        let store = RecoveryStore(directory: AppTestSupport.tempDir())
        let leftover = RecoveryEntry(id: UUID(), name: "From a crash", savedAt: Date())
        try store.write(KerfProject(), entry: leftover)
        let c = RecoveryCoordinator(store: store)
        let a = makeDoc(), b = makeDoc()
        c.register(a); c.register(b)
        a.perform("A") { $0.document.name = "A" }
        b.perform("B") { $0.document.name = "B" }
        c.tick()
        #expect(store.entries().count == 3)
        c.unregister(a)
        #expect(Set(store.entries().map(\.name)) == ["B", "From a crash"])
        c.cleanUpOnQuit()
        #expect(store.entries().map(\.id) == [leftover.id])
    }

    @Test func undoBackToSavedStateIsClean() {
        let doc = makeDoc()
        let um = UndoManager()
        um.groupsByEvent = false
        doc.undoManager = um
        um.beginUndoGrouping(); doc.perform("Rename") { $0.document.name = "X" }; um.endUndoGrouping()
        #expect(doc.needsRecovery)
        um.undo()
        #expect(!doc.needsRecovery)
    }
}
