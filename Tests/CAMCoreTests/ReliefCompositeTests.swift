import CADCore
import Foundation
import Testing
@testable import CAMCore

private let ballNose = ToolLibrary.seeded.tools[3]  // 1/4" ball nose

/// 6 x 4 x 1.25 in job with two unit domes (top at the material top, bottom 1 in deep) centred at
/// (2, 2) and (4.5, 2); the second one is only 0.6 in deep.
private func twoDomes() -> (Document, PlacedModel, PlacedModel) {
    var doc = Document(units: .inch, job: JobSetup(width: 6, height: 4, thickness: 1.25))
    let a = PlacedModel(name: "A", mesh: ReliefFixture.hemisphere(radius: 1, center: Vec2(2, 2)), depth: 1, zTop: 0)
    let b = PlacedModel(name: "B", mesh: ReliefFixture.hemisphere(radius: 1, center: Vec2(4.5, 2)), depth: 0.6, zTop: 0)
    doc.models = [a, b]
    return (doc, a, b)
}

private func finishOp(_ primary: PlacedModel, combine: [UUID]?) -> Relief3DOperation {
    var p = Relief3DParameters(modelID: primary.id, resolution: 0.02,
                               roughing: RoughingSettings(isEnabled: false),
                               finishing: FinishingSettings(isEnabled: true, stepover: 0.1, angle: 0))
    p.additionalModelIDs = combine
    return Relief3DOperation(setup: OperationSetup(name: "Domes", toolID: ballNose.id), params: p)
}

@Test func reliefCompositeHeightmapKeepsShallowestModel() throws {
    let (_, a, b) = twoDomes()
    let area = Rect2(x: 0.5, y: 0.5, width: 5.5, height: 3)
    let map = try ReliefHeightmap.rasterize([a, b], over: area, cellSize: 0.05)
    #expect(map.baseDepth == 1) // deepest bottom plane
    func cell(_ p: Vec2) -> Double {
        map[Int(((p.x - area.min.x) / 0.05).rounded()), Int(((p.y - area.min.y) / 0.05).rounded())]
    }
    #expect(cell(Vec2(2, 2)) < 0.01)
    #expect(cell(Vec2(4.5, 2)) < 0.01)
    #expect(abs(cell(Vec2(1, 3.4)) - 1) < 1e-9) // outside both
    // On B's flank, B's own depth mapping (0.6 deep at its rim) applies.
    #expect(cell(Vec2(5.45, 2)) < 0.6 + 1e-9)
}

@Test func reliefCompositeMachinesEveryModel() throws {
    let (doc, a, b) = twoDomes()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let single = try #require(finishOp(a, combine: nil).generate(in: ctx).first)
    let both = try #require(finishOp(a, combine: [b.id, a.id, b.id]).generate(in: ctx).first)
    func xs(_ tp: Toolpath) -> Rect2 { Rect2(points: tp.moves.filter { !$0.isRapid }.compactMap { $0.target?.xy }) }
    // Alone, only A's footprint is machined; combined, the area spans both domes.
    #expect(xs(single).max.x < 3.01)
    #expect(xs(both).max.x > 5.4)
    #expect(xs(both).min.x < 1.01)
    #expect(ReliefFixture.followsConventions(both, coords: ctx.coords))
    // The finish reaches both apexes.
    let samples = ReliefFixture.cutSamples(both, coords: ctx.coords, step: 0.05)
    for apex in [Vec2(2, 2), Vec2(4.5, 2)] {
        let near = samples.filter { $0.0.distance(to: apex) < 0.06 }.map(\.1)
        #expect((near.min() ?? 1) < 0.02)
    }
    #expect(both.metadata["warning"] == nil)
}

@Test func reliefCompositeSkipsMissingModelsWithWarning() throws {
    let (doc, a, _) = twoDomes()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let tp = try #require(finishOp(a, combine: [UUID()]).generate(in: ctx).first)
    #expect(tp.metadata["warning"]?.contains("missing") == true)
}

@Test func reliefParametersDecodeWithoutCompositeField() throws {
    let p = Relief3DParameters(modelID: UUID())
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
    json.removeValue(forKey: "additionalModelIDs")
    let back = try JSONDecoder().decode(Relief3DParameters.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(back.additionalModelIDs == nil)
    #expect(back.allModelIDs == [p.modelID])
}
