import CADCore
import CAMCore
import Foundation
import Testing
@testable import LoftLineApp

/// A cut depth set from the material thickness moves with it when Job Setup changes the thickness.
@Suite struct DepthFollowsThicknessTests {
    private func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-9) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    func project() -> LoftLineProject {
        var p = AppTestSupport.project()
        p.document.job.thickness = 0.75
        return p
    }

    func profile(_ p: LoftLineProject, depth: Double, follows: Bool?) -> AnyOperation {
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

    @Test func onlyTheEditedSheetsOperationsFollow() {
        // Sheet A is 0.75 thick, sheet B 0.5; each has a following through profile.
        var p = project()
        let bJob = JobSetup(width: 10, height: 10, thickness: 0.5)
        p.document.addSheet(name: "B", job: bJob, layerName: "B", colorHex: "#336699")
        let bLayer = p.document.layers.last!.id
        p.document.shapes[1].layerID = bLayer
        let a = p.document.shapes[0].id, b = p.document.shapes[1].id
        var onA = profile(p, depth: 0.75, follows: true); onA.editableSetup.shapeIDs = [a]
        var onB = profile(p, depth: 0.5, follows: true); onB.editableSetup.shapeIDs = [b]
        p.operations = [onA, onB]
        #expect(p.sheetID(of: onB) != p.document.currentSheetID)
        var form = JobSetupForm(document: p.document)
        form.job.thickness = 0.78
        let out = form.apply(to: p)
        #expect(approx(out.operations[0].editableDepth?.cutDepth, 0.78))
        #expect(approx(out.operations[1].editableDepth?.cutDepth, 0.5))
        #expect(out.document.job(ofSheet: p.document.allSheets[1].id)?.thickness == 0.5)
    }

    @Test(arguments: [ZZeroMode.materialTop, ZZeroMode.spoilboard])
    func thePartsOfAMergedOperationFollow(zZero: ZZeroMode) throws {
        var p = project()
        p.document.job.zZero = zZero
        var fixed = profile(p, depth: 0.4, follows: nil)
        fixed.editableSetup.shapeIDs = [p.document.shapes[1].id]
        p.operations = [profile(p, depth: 0.75, follows: true), profile(p, depth: 0.77, follows: true), fixed]
        p.mergeWithNext(p.operations[0].id)
        p.mergeWithNext(p.operations[0].id)
        guard case .merge = p.operations[0] else { throw Failure.notMerged }
        for thickness in [0.72, 0.8] {
            var form = JobSetupForm(document: p.document)
            form.job.thickness = thickness
            let out = form.apply(to: p)
            guard case .merge(let m) = out.operations[0] else { throw Failure.notMerged }
            let depths = m.params.children.map { $0.editableDepth!.cutDepth }
            #expect(approx(depths[0], thickness) && approx(depths[1], thickness + 0.02) && approx(depths[2], 0.4),
                    Comment(rawValue: "\(thickness): \(depths)"))
            // The generated toolpath reaches the new bottom (plus the overcut) and no further.
            let tps = try out.operations[0].generate(in: CAMContext(document: out.document, tools: .seeded))
            let lowest = tps.flatMap(\.moves).compactMap { $0.target?.z }.min()!
            #expect(approx(lowest, MachineCoordinates(job: out.document.job).z(depth: thickness + 0.02), 1e-6))
        }
    }

    enum Failure: Error { case notMerged }

    @Test func noChangeInThicknessChangesNothing() {
        var p = project()
        p.operations = [profile(p, depth: 0.77, follows: true)]
        let out = JobSetupForm(document: p.document).apply(to: p)
        #expect(out.operations == p.operations)
    }
}
