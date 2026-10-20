import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

/// A cut depth set from the material thickness moves with it when Job Setup changes the thickness.
@Suite struct DepthFollowsThicknessTests {
    private func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-9) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    func project() -> KerfProject {
        var p = AppTestSupport.project()
        p.document.job.thickness = 0.75
        return p
    }

    func profile(_ p: KerfProject, depth: Double, follows: Bool?) -> AnyOperation {
        var op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: p.document.shapes.map(\.id))!
        var d = op.editableDepth!
        d.cutDepth = depth
        d.followsThickness = follows
        op.editableDepth = d
        return op
    }

    @Test func aNewProfileCutsThroughAndFollows() {
        let p = project()
        let op = OperationFactory.make(kind: .profile, project: p, library: .seeded, shapeIDs: [])!
        #expect(approx(op.editableDepth?.cutDepth, 0.75))
        #expect(op.editableDepth?.followsThickness == true)
        let pocket = OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: [])!
        #expect(pocket.editableDepth?.followsThickness == nil)
    }

    @Test func jobSetupMovesFollowingDepthsAndLeavesTheRest() {
        var p = project()
        p.operations = [
            profile(p, depth: 0.75, follows: true),     // through
            profile(p, depth: 0.77, follows: true),     // through with an overcut
            profile(p, depth: 0.75, follows: nil),      // fixed by hand
            OperationFactory.make(kind: .pocket, project: p, library: .seeded, shapeIDs: [])!,   // 0.25, fixed
        ]
        var form = JobSetupForm(document: p.document)
        form.job.thickness = 0.5
        let out = form.apply(to: p)
        let depths = out.operations.map { $0.editableDepth!.cutDepth }
        #expect(approx(depths[0], 0.5))
        #expect(approx(depths[1], 0.52))
        #expect(approx(depths[2], 0.75))
        #expect(approx(depths[3], 0.25))
        // The flags survive, so the next change follows too.
        #expect(out.operations[0].editableDepth?.followsThickness == true)
    }

    @Test func aUnitChangeAndAThicknessChangeTogether() {
        var p = project()
        p.operations = [profile(p, depth: 0.77, follows: true)]
        var form = JobSetupForm(document: p.document)
        form.setUnits(.millimeter)          // 0.75 in -> 19.05 mm
        form.job.thickness = 18
        let out = form.apply(to: p)
        #expect(out.document.units == .millimeter)
        // 0.02 in past the bottom stays 0.508 mm past the bottom.
        #expect(approx(out.operations[0].editableDepth?.cutDepth, 18 + 0.02 * 25.4, 1e-6))
    }

    @Test func handEditedPassesPastTheNewDepthAreDropped() {
        var p = project()
        var op = profile(p, depth: 0.75, follows: true)
        var d = op.editableDepth!
        d.customPasses = [0.25, 0.5]
        op.editableDepth = d
        p.operations = [op]
        var form = JobSetupForm(document: p.document)
        form.job.thickness = 0.4
        let out = form.apply(to: p)
        #expect(approx(out.operations[0].editableDepth?.cutDepth, 0.4))
        #expect(out.operations[0].editableDepth?.customPasses == [0.25])
    }

    @Test func noChangeInThicknessChangesNothing() {
        var p = project()
        p.operations = [profile(p, depth: 0.77, follows: true)]
        let out = JobSetupForm(document: p.document).apply(to: p)
        #expect(out.operations == p.operations)
    }
}
