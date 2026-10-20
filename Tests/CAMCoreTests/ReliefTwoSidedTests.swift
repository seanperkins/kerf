import CADCore
import Foundation
import Testing
@testable import CAMCore

private let ballNose = ToolLibrary.seeded.tools[3]  // 1/4" ball nose

/// 4 x 4 x 1.25 in job; unit dome centred at (1.5, 2), top 0.1 below the material top, flat
/// underside 1.1 below it.
private func offCentreDome() -> (Document, PlacedModel) {
    var doc = Document(units: .inch, job: JobSetup(width: 4, height: 4, thickness: 1.25))
    let model = PlacedModel(name: "Dome", mesh: ReliefFixture.hemisphere(radius: 1, center: Vec2(1.5, 2)),
                            depth: 1.1, zTop: 0.1)
    doc.models = [model]
    return (doc, model)
}

private func sideOp(_ model: PlacedModel, side: TwoSidedSettings.Side, flip: TwoSidedSettings.Flip = .leftRight,
                    split: Double? = 0.6, web: Double = 0.04) -> Relief3DOperation {
    var p = Relief3DParameters(modelID: model.id, resolution: 0.02, roughing: RoughingSettings(isEnabled: false),
                               finishing: FinishingSettings(isEnabled: true, stepover: 0.1))
    p.twoSided = TwoSidedSettings(side: side, flip: flip, splitDepth: split, web: web)
    return Relief3DOperation(setup: OperationSetup(name: "Dome", toolID: ballNose.id), params: p)
}

private func cuts(_ tp: Toolpath, _ c: MachineCoordinates) -> [(xy: Vec2, depth: Double)] {
    ReliefFixture.cutSamples(tp, coords: c, step: 0.05).map { (xy: $0.0, depth: $0.1) }
}

@Test func reliefTwoSidedTopStopsAtSplit() throws {
    let (doc, model) = offCentreDome()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let tp = try #require(sideOp(model, side: .top).generate(in: ctx).first)
    #expect(tp.metadata["side"] == "top")
    let pts = cuts(tp, ctx.coords)
    #expect(abs(pts.map(\.depth).max()! - 0.6) < 1e-6)            // clamped at the split
    #expect(pts.map(\.depth).min()! < 0.12)                        // dome top (0.1 deep)
    #expect(pts.allSatisfy { $0.xy.x < 2.6 })                      // dome is on the left
}

@Test(arguments: [TwoSidedSettings.Flip.leftRight, .topBottom])
func reliefTwoSidedBottomIsMirroredAndStopsShortOfSplit(flip: TwoSidedSettings.Flip) throws {
    let (doc, model) = offCentreDome()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let tp = try #require(sideOp(model, side: .bottom, flip: flip).generate(in: ctx).first)
    #expect(tp.metadata["side"] == "bottom")
    #expect(ReliefFixture.followsConventions(tp, coords: ctx.coords))
    let pts = cuts(tp, ctx.coords)
    // Seen from below: the flat underside is 1.25 - 1.1 = 0.15 deep; around it the cut stops at
    // 1.25 - 0.6 - 0.04 = 0.61 (leaving the web).
    #expect(abs(pts.map(\.depth).max()! - 0.61) < 1e-6)
    let centre = flip == .leftRight ? Vec2(2.5, 2) : Vec2(1.5, 2)
    let under = pts.filter { $0.xy.distance(to: centre) < 0.6 }
    #expect(!under.isEmpty)
    #expect(under.allSatisfy { abs($0.depth - 0.15) < 0.01 })
    // The footprint is mirrored.
    let b = Rect2(points: pts.map(\.xy))
    if flip == .leftRight {
        #expect(b.min.x > 1.4 && b.max.x < 3.6)
    } else {
        #expect(b.min.x < 0.6 && b.max.x < 2.6)
    }
}

@Test func reliefTwoSidedRejectsBadSplit() {
    let (doc, model) = offCentreDome()
    let ctx = CAMContext(document: doc, tools: .seeded)
    #expect(throws: CAMError.self) { try sideOp(model, side: .top, split: 0.05).generate(in: ctx) }
    #expect(throws: CAMError.self) { try sideOp(model, side: .bottom, split: 1.2).generate(in: ctx) }
    #expect(throws: CAMError.self) { try sideOp(model, side: .bottom, split: 0.6, web: 0.7).generate(in: ctx) }
    // Default split: halfway between top (0.1) and bottom (1.1).
    #expect(abs(ReliefTwoSided.splitDepth(TwoSidedSettings(), model: model) - 0.6) < 1e-12)
}
