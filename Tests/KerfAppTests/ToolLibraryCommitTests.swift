import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

/// A Tool Database edit is one write of tools.json, and only an edit that can change a toolpath
/// makes open documents' toolpaths stale.
@MainActor
@Suite struct ToolLibraryCommitTests {
    func edit(_ lib: ToolLibraryModel, _ change: (inout Tool) -> Void) throws -> Tool {
        var t = try #require(lib.tools.first)
        change(&t)
        return t
    }

    @Test func aNameEditIsOneWriteAndNoStaleMark() throws {
        let lib = AppTestSupport.library()
        let before = (lib.writes, lib.revision)
        #expect(lib.commitEdit(try edit(lib) { $0.name = "Renamed bit" }))
        #expect(lib.writes == before.0 + 1)
        #expect(lib.revision == before.1)
        #expect(ToolLibraryModel(store: lib.store).tools.first?.name == "Renamed bit")
    }

    @Test func notesAndFolderAreLabelsToo() throws {
        let lib = AppTestSupport.library()
        let r = lib.revision
        #expect(lib.commitEdit(try edit(lib) { $0.notes = "Bought at the show" }))
        #expect(lib.commitEdit(try edit(lib) { $0.group = "Favourites" }))
        #expect(lib.revision == r)
        #expect(lib.writes == 2)
    }

    @Test func aDiameterEditIsOneWriteAndOneStaleMark() throws {
        let lib = AppTestSupport.library()
        let before = (lib.writes, lib.revision)
        #expect(lib.commitEdit(try edit(lib) { $0.diameter += 0.01 }))
        #expect(lib.writes == before.0 + 1)
        #expect(lib.revision == before.1 + 1)
    }

    @Test func everyFieldThatReachesTheProgramMarksToolpathsStale() throws {
        let changes: [(String, (inout Tool) -> Void)] = [
            ("feed", { $0.feedRate += 1 }), ("plunge", { $0.plungeRate += 1 }), ("rpm", { $0.spindleRPM += 100 }),
            ("stepdown", { $0.stepdown /= 2 }), ("stepover", { $0.stepover /= 2 }), ("flutes", { $0.flutes += 1 }),
            ("number", { $0.number += 40 }), ("kind", { $0.kind = .ballNose }), ("units", { $0 = $0.converted(to: .millimeter) }),
            ("flute length", { $0.fluteLength = 0.2 }),
            ("material data", { $0.materials = [MaterialCuttingData(material: "Oak", from: $0)] }),
        ]
        for (name, change) in changes {
            let lib = AppTestSupport.library()
            let r = lib.revision
            #expect(lib.commitEdit(try edit(lib, change)), Comment(rawValue: name))
            #expect(lib.revision == r + 1, Comment(rawValue: name))
        }
    }

    @Test func addingOrRemovingAToolMarksToolpathsStale() throws {
        let lib = AppTestSupport.library()
        var r = lib.revision
        let added = lib.add(kind: .endMill)
        #expect(lib.revision == r + 1); r = lib.revision
        lib.delete(id: added.id)
        #expect(lib.revision == r + 1)
    }

    @Test func aChangeThatChangesNothingWritesNothing() throws {
        let lib = AppTestSupport.library()
        let first = try #require(lib.tools.first)
        lib.update(first)
        lib.restoreDefaults()
        lib.delete(id: UUID())
        lib.importTools([first])
        #expect(lib.writes == 0)
        #expect(lib.revision == 0)
    }

    /// The document side: a renamed tool leaves calculated toolpaths valid, a re-sized one does not.
    @Test func documentsGoStaleOnlyForAnEditThatCanChangeTheirToolpaths() throws {
        let lib = AppTestSupport.library()
        var p = AppTestSupport.project()
        let tool = try #require(lib.tools.first { $0.kind == .endMill })
        var op = try #require(OperationFactory.make(kind: .profile, project: p, library: lib.library,
                                                    shapeIDs: [p.document.shapes[0].id]))
        var s = op.editableSetup
        s.toolID = tool.id
        op.editableSetup = s
        p.operations = [op]
        let doc = KerfDocument(project: p, toolLibrary: lib)
        doc.calculateNow([op.id])
        #expect(!doc.isStale(op.id))

        var renamed = tool
        renamed.name = "Renamed bit"
        renamed.notes = "Dull"
        #expect(lib.commitEdit(renamed))
        #expect(!doc.isStale(op.id))

        var wider = renamed
        wider.diameter += 0.05
        #expect(lib.commitEdit(wider))
        #expect(doc.isStale(op.id))
    }
}
