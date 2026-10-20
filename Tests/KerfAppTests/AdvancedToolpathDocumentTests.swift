import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

/// KerfDocument wiring for the inlay wizard, STL placement dialog and tab editor.
@Suite struct AdvancedToolpathDocumentTests {
    func makeDoc() -> (KerfDocument, UndoManager) {
        let doc = KerfDocument(project: AppTestSupport.project(), toolLibrary: AppTestSupport.library())
        let um = UndoManager()
        um.groupsByEvent = false
        doc.undoManager = um
        return (doc, um)
    }

    func step(_ um: UndoManager, _ body: () -> Void) {
        um.beginUndoGrouping(); body(); um.endUndoGrouping()
    }

    static let stl = """
    solid t
    facet normal 0 0 1
    outer loop
    vertex 0 0 0
    vertex 2 0 0
    vertex 1 1 0.5
    endloop
    endfacet
    facet normal 0 0 1
    outer loop
    vertex 0 0 0
    vertex 1 1 0.5
    vertex 0 2 0
    endloop
    endfacet
    endsolid t
    """

    @Test func newInlayOpensTheWizard() {
        let (doc, _) = makeDoc()
        doc.addOperation(.inlay)
        #expect(doc.sheet == .inlayWizard)
        #expect(doc.project.operations.isEmpty)
    }

    @Test func wizardAddsBothInlayToolpathsInOneUndoStep() {
        let (doc, um) = makeDoc()
        let w = InlayWizardModel(project: doc.project, library: doc.mergedLibrary, shapeIDs: [doc.document.shapes[0].id])
        step(um) { doc.addInlay(w) }
        #expect(doc.project.operations.count == 2)
        #expect(doc.selectedOperationID == doc.project.operations[0].id)
        um.undo()
        #expect(doc.project.operations.isEmpty)
    }

    @Test func importingAnSTLShowsThePlacementDialog() throws {
        let (doc, um) = makeDoc()
        let url = AppTestSupport.tempDir().appendingPathComponent("bump.stl")
        try Data(Self.stl.utf8).write(to: url)
        doc.importFiles([url])
        guard case .placeModel(let form) = doc.sheet else { Issue.record("expected placement sheet"); return }
        #expect(form.name == "bump")
        #expect(doc.document.models.isEmpty) // nothing changes until the dialog is accepted
        step(um) { doc.applyPlacement(form) }
        #expect(doc.document.models.count == 1)
        #expect(doc.project.operations.map(\.setup.name) == ["bump Roughing", "bump Finishing"])
        um.undo()
        #expect(doc.document.models.isEmpty && doc.project.operations.isEmpty)
    }

    @Test func editingAPlacementUpdatesTheModelInPlace() {
        let (doc, um) = makeDoc()
        var f = ModelPlacementForm(mesh: ModelPlacementFormTests.mesh, name: "Pyr", job: doc.document.job,
                                   library: doc.mergedLibrary)
        f.createToolpaths = false
        step(um) { doc.applyPlacement(f) }
        doc.editPlacement(of: f.modelID)
        guard case .placeModel(var e) = doc.sheet else { Issue.record("expected placement sheet"); return }
        e.zHeight = 0.25
        step(um) { doc.applyPlacement(e) }
        #expect(doc.document.models.count == 1)
        #expect(abs(doc.document.models[0].depth - 0.25) < 1e-12)
        #expect(doc.project.operations.isEmpty)
    }

    @Test func tabEditsAreUndoableAndEditingEndsWhenTheToolpathGoes() throws {
        let (doc, um) = makeDoc()
        doc.setSelection([doc.document.shapes[0].id])
        step(um) { doc.addOperation(.profile) }
        let id = try #require(doc.selectedOperationID)
        doc.tabEditingOperationID = id
        let tabs = try #require(TabEditor.adding(at: Vec2(2, 1), to: TabSettings(), shapes: doc.selectedShapes,
                                                 maxDistance: 0.1, tolerance: 0.001))
        step(um) { doc.setProfileTabs(tabs, for: id, actionName: "Add Tab") }
        #expect(doc.operation(id)?.profileTabs?.manualTabs?.count == 1)
        #expect(um.undoActionName == "Add Tab")
        um.undo()
        #expect(doc.operation(id)?.profileTabs?.manualTabs == nil)
        step(um) { doc.deleteOperation(id) }
        #expect(doc.tabEditingOperationID == nil)
    }
}
