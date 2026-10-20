import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct UnitScalingTests {
    @Test func convertingProjectToMillimetresScalesEverything() {
        var p = AppTestSupport.project()
        let op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [p.document.shapes[0].id])!
        p.operations = [op]
        let mm = p.converted(to: .millimeter)
        #expect(mm.document.units == .millimeter)
        #expect(abs(mm.document.job.width - 24 * 25.4) < 1e-9)
        #expect(abs(mm.document.gridSpacing - 0.25 * 25.4) < 1e-9)
        #expect(abs(mm.document.shapes[0].bounds().min.x - 25.4) < 1e-6)
        guard case .profile(let o) = mm.operations[0] else { Issue.record("kind changed"); return }
        #expect(abs(o.params.depth.cutDepth - 0.75 * 25.4) < 1e-9)
        #expect(abs(o.params.tabs.length - 0.25 * 25.4) < 1e-9)
        #expect(o.params.ramp.maxAngle == 10) // angles are not scaled
    }

    @Test func sameUnitsIsIdentity() {
        let p = AppTestSupport.project()
        #expect(p.converted(to: .inch) == p)
    }
}

@Suite struct OperationFactoryTests {
    @Test func picksSuitableDefaultTools() {
        let lib = ToolLibrary.seeded
        #expect(OperationFactory.defaultTool(for: .vcarve, in: lib)?.kind == .vBit)
        #expect(OperationFactory.defaultTool(for: .drill, in: lib)?.kind == .drill)
        #expect(OperationFactory.defaultTool(for: .profile, in: lib)?.kind == .endMill)
        #expect(OperationFactory.defaultTool(for: .fluting, in: lib)?.kind == .ballNose)
    }

    @Test func profileCutsThroughMaterialByDefault() {
        let p = AppTestSupport.project()
        guard case .profile(let o) = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: []) else {
            Issue.record("expected profile"); return
        }
        #expect(o.params.depth.cutDepth == p.document.job.thickness)
    }

    @Test func millimetreDocumentsGetScaledDefaults() {
        let p = AppTestSupport.project().converted(to: .millimeter)
        guard case .pocket(let o) = OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: []) else {
            Issue.record("expected pocket"); return
        }
        #expect(abs(o.params.depth.cutDepth - 0.25 * 25.4) < 1e-9)
    }

    @Test func reliefNeedsAModel() {
        var p = AppTestSupport.project()
        #expect(OperationFactory.make(kind: .relief3D, project: p, library: .seeded, shapeIDs: []) == nil)
        p.document.models.append(PlacedModel(name: "m", mesh: Mesh3D()))
        #expect(OperationFactory.make(kind: .relief3D, project: p, library: .seeded, shapeIDs: []) != nil)
    }

    @Test func namesAreUnique() {
        var p = AppTestSupport.project()
        let a = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [])!
        p.operations.append(a)
        let b = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [])!
        #expect(a.setup.name == "Profile 1")
        #expect(b.setup.name == "Profile 2")
    }

    @Test func editableSetupRoundTrips() {
        let p = AppTestSupport.project()
        var op = OperationFactory.make(kind: .vcarve, project: p, library: .seeded, shapeIDs: [])!
        var s = op.editableSetup
        s.name = "Letters"
        op.editableSetup = s
        #expect(op.setup.name == "Letters")
        #expect(op.kind == .vcarve)
    }
}

@Suite struct ProjectEditingTests {
    @Test func deletingShapesDropsThemFromOperations() {
        var p = AppTestSupport.project()
        let ids = p.document.shapes.map(\.id)
        p.operations = [OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: ids)!]
        p.deleteShapes([ids[0]])
        #expect(p.document.shapes.count == 1)
        #expect(p.operations[0].setup.shapeIDs == [ids[1]])
    }

    @Test func deletingLayerMovesShapesAndKeepsLastLayer() {
        var p = AppTestSupport.project()
        let l2 = p.addLayer(named: "Two")
        p.moveShapes([p.document.shapes[0].id], toLayer: l2)
        p.deleteLayer(l2)
        #expect(p.document.layers.count == 1)
        #expect(p.document.shapes.allSatisfy { $0.layerID == p.document.defaultLayerID })
        p.deleteLayer(p.document.defaultLayerID)
        #expect(p.document.layers.count == 1)
    }

    @Test func lockedLayerShapesAreNotEditable() {
        var p = AppTestSupport.project()
        var layer = p.document.layers[0]
        layer.isLocked = true
        p.updateLayer(layer)
        #expect(!p.isEditable(p.document.shapes[0]))
    }

    @Test func reorderOperations() {
        var p = AppTestSupport.project()
        let a = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [])!
        p.operations.append(a)
        let b = OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: [])!
        p.operations.append(b)
        p.moveOperation(b.id, by: -1)
        #expect(p.operations.map(\.id) == [b.id, a.id])
        p.moveOperation(b.id, by: -1) // already first: no-op
        #expect(p.operations.map(\.id) == [b.id, a.id])
    }

    @Test func toolSnapshotIncludesSecondaryTools() {
        var p = AppTestSupport.project()
        guard case .pocket(var o) = OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: []) else {
            Issue.record("expected pocket"); return
        }
        o.params.clearanceToolID = ToolLibrary.seeded.tools[2].id
        p.operations = [.pocket(o)]
        p.refreshToolSnapshot(from: .seeded)
        #expect(Set(p.tools.map(\.id)) == [o.setup.toolID, ToolLibrary.seeded.tools[2].id])
    }

    @Test func duplicateOffsetsCopies() {
        var p = AppTestSupport.project()
        let src = p.document.shapes[0]
        let ids = p.duplicateShapes([src.id], offset: Vec2(1, 0))
        #expect(ids.count == 1)
        let copy = p.document.shape(id: ids[0])!
        #expect(abs(copy.bounds().min.x - (src.bounds().min.x + 1)) < 1e-9)
    }
}

@Suite struct JobSetupFormTests {
    @Test func switchingUnitsConvertsFormValues() {
        var f = JobSetupForm(document: Document())
        f.setUnits(.millimeter)
        #expect(abs(f.job.width - 609.6) < 1e-9)
        #expect(abs(f.job.thickness - 19.05) < 1e-9)
        #expect(f.problems.isEmpty)
    }

    @Test func applyConvertsProjectAndSetsJob() {
        let p = AppTestSupport.project()
        var f = JobSetupForm(document: p.document)
        f.setUnits(.millimeter)
        f.job.xyOrigin = .center
        f.job.zZero = .spoilboard
        let out = f.apply(to: p)
        #expect(out.document.units == .millimeter)
        #expect(out.document.job.xyOrigin == .center)
        #expect(out.document.job.zZero == .spoilboard)
        #expect(abs(out.document.shapes[0].bounds().min.x - 25.4) < 1e-6)
    }

    @Test func invalidValuesReportProblems() {
        var f = JobSetupForm(document: Document())
        f.job.thickness = 0
        f.job.safeZ = -1
        #expect(f.problems.count >= 2)
    }
}
