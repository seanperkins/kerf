import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// Regressions found in the 2026-10-20 deep review (docs/REVIEW-2026-10-20.md).
@Suite struct ReviewRegressionTests {
    /// Two parts far apart with automatic tabs and a last pass: the finishing lap used to lay
    /// its tabs out afresh from wherever it started, so they landed away from the roughing tabs
    /// and the lap cut the roughing tabs away. Every raised section of the finishing lap must sit
    /// on a raised section of the roughing passes.
    @Test(arguments: [ZZeroMode.materialTop, .spoilboard])
    func lastPassFinishesAtTheRoughingTabs(mode: ZZeroMode) throws {
        let (ctx, ids) = F.document([F.rect(1, 1, 3, 2), F.rect(8, 6, 3, 2)], zZero: mode)
        var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: .outside,
                                  lastPass: ProfileLastPass(allowance: 0.02))
        p.tabs = TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
        let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
        let tp = try op.generate(in: ctx)[0]
        let c = ctx.coords
        let tabZ = c.z(depth: 0.4)
        let rects = [Rect2(x: 1, y: 1, width: 3, height: 2), Rect2(x: 8, y: 6, width: 3, height: 2)]
        func wall(_ q: Vec2) -> Double { rects.map { F.distanceToRectBoundary(c.materialXY(fromMachine: q), $0) }.min()! }
        let raised = F.densePoints(tp.moves).filter { abs($0.z - tabZ) < 1e-9 }.map(\.xy)
        let roughRaised = raised.filter { abs(wall($0) - 0.145) < 0.002 }
        let finishRaised = raised.filter { abs(wall($0) - 0.125) < 0.002 }
        #expect(roughRaised.count > 8 && finishRaised.count > 8)
        for q in finishRaised {
            let nearest = roughRaised.map { $0.distance(to: q) }.min()!
            #expect(nearest < 0.05, "finishing tab at \(q) is \(nearest) from any roughing tab")
        }
        #expect(F.conventionViolations(tp, coords: c).isEmpty)
    }

    /// A tile is its own program zeroed at its corner: the whole job's datum offset and home
    /// must not shift it or send the footer's move home off the tile.
    @Test func tilesDropTheDatumOffsetAndHome() {
        var job = JobSetup(width: 120, height: 48, thickness: 0.75, xyOrigin: .lowerLeft, zZero: .materialTop, safeZ: 0.5)
        job.datumOffset = Vec2(1, 2)
        job.home = Vec2(-5, -5)
        let coords = MachineCoordinates(job: job)
        let tool = ToolLibrary.seeded.tools[0]
        let tp = Toolpath(name: "L", kind: .profile, tool: tool, moves: [
            .rapid(to: coords.machineAtSafeZ(Vec2(10, 10))),
            .linear(to: coords.machine(Vec2(10, 10), depth: 0.25), feed: 30),
            .linear(to: coords.machine(Vec2(20, 10), depth: 0.25), feed: 100),
            .rapid(to: coords.machineAtSafeZ(Vec2(20, 10))),
        ])
        let tiles = ToolpathTiling.tile([tp], job: job, units: .inch, settings: TilingSettings(tileWidth: 60, tileHeight: 96))
        let first = tiles[0]
        #expect(first.job.datumOffset == nil && first.job.home == .zero)
        // Material (10, 10) is machine (10, 10) in a tile whose corner is the material corner.
        let cut = first.toolpaths[0].moves.compactMap { m -> Vec3? in if case .linear(let p, _) = m { return p } else { return nil } }
        #expect(cut.first?.xy.isApproximatelyEqual(to: Vec2(10, 10), tolerance: 1e-9) == true)
    }

    /// Bounds are a safety test for reordering toolpaths, so an arc's bulge counts, not only
    /// its end points: a circle made of two half arcs spans its diameter in both axes.
    @Test func toolpathBoundsIncludeArcBulges() {
        let tool = ToolLibrary.seeded.tools[0]
        let tp = Toolpath(name: "O", kind: .profile, tool: tool, moves: [
            .rapid(to: Vec3(6, 5, 0.2)),
            .linear(to: Vec3(6, 5, -0.1), feed: 30),
            .arcCCW(to: Vec3(4, 5, -0.1), center: Vec2(5, 5), feed: 100),
            .arcCCW(to: Vec3(6, 5, -0.1), center: Vec2(5, 5), feed: 100),
            .rapid(to: Vec3(6, 5, 0.2)),
        ])
        let b = tp.xyBounds
        #expect(abs(b.min.x - 4) < 1e-9 && abs(b.max.x - 6) < 1e-9)
        #expect(abs(b.min.y - 4) < 1e-9 && abs(b.max.y - 6) < 1e-9)
        // A quarter arc from 3 o'clock to 12 o'clock bulges to neither 9 nor 6 o'clock.
        let quarter = Toolpath(name: "q", kind: .profile, tool: tool, moves: [
            .rapid(to: Vec3(6, 5, -0.1)), .arcCCW(to: Vec3(5, 6, -0.1), center: Vec2(5, 5), feed: 100),
        ])
        let q = quarter.xyBounds
        #expect(abs(q.min.x - 5) < 1e-9 && abs(q.min.y - 5) < 1e-9 && abs(q.max.x - 6) < 1e-9 && abs(q.max.y - 6) < 1e-9)
    }

    /// A template must not carry references to the design's models either.
    @Test func templatesDropModelReferences() {
        var setup = OperationSetup(name: "R", toolID: ToolLibrary.seeded.tools[0].id, shapeIDs: [UUID()])
        setup.projectOntoModelID = UUID()
        var params = Relief3DParameters(modelID: UUID())
        params.additionalModelIDs = [UUID()]
        params.boundaryShapeIDs = [UUID()]
        let detached = AnyOperation.relief3D(Relief3DOperation(setup: setup, params: params)).detachedFromDesign()
        #expect(detached.setup.projectOntoModelID == nil && detached.setup.shapeIDs.isEmpty)
        guard case .relief3D(let r) = detached else { Issue.record("not a relief"); return }
        #expect(r.params.additionalModelIDs == nil && r.params.boundaryShapeIDs.isEmpty)
    }

    /// A region too small for one stroke is an error, not a toolpath with no moves.
    @Test func textureWithNoStrokesThrows() {
        let (ctx, ids) = F.document([F.rect(0, 0, 0.2, 0.2)])
        let op = TextureOperation(setup: OperationSetup(name: "T", toolID: F.endMill.id, shapeIDs: ids),
                                  params: TextureParameters(maxDepth: 0.05, spacing: 0.1, minStrokeLength: 1))
        #expect(throws: CAMError.self) { try op.generate(in: ctx) }
    }

    /// Inlay depth checks compare what is really cut with the stock thickness.
    @Test func inlayDepthsAreCheckedAgainstTheStock() {
        let (ctx, ids) = F.document([ShapeFactory.circle(center: Vec2(3, 3), radius: 1)])
        let vbit = ToolLibrary.seeded.tools[5]
        let deepMale = InlayParameters(part: .male, pocketDepth: 0.2, maleStartDepth: 0.1, surfaceClearance: 0.7)
        #expect(throws: CAMError.self) {
            try InlayOperation(setup: OperationSetup(name: "I", toolID: vbit.id, shapeIDs: ids), params: deepMale).generate(in: ctx)
        }
        let deepPocket = InlayParameters(part: .female, pocketDepth: 0.8, maleStartDepth: 0.1)
        #expect(throws: CAMError.self) {
            try InlayOperation(setup: OperationSetup(name: "I", toolID: vbit.id, shapeIDs: ids), params: deepPocket).generate(in: ctx)
        }
    }

    /// A tiny peck cannot produce millions of moves.
    @Test func peckCountIsBounded() {
        let pecks = DrillOperation.peckDepths(start: 0, end: 0.5, peck: 1e-7)
        #expect(pecks.count <= DepthSettings.maxComputedPasses + 1)
        #expect(abs(pecks.last! - 0.5) < 1e-12)
    }
}
