import CADCore
import Foundation
import Testing
@testable import CAMCore

private let ballNose = ToolLibrary.seeded.tools[3]  // 1/4" ball nose

private func finishOp(_ model: PlacedModel, strategy: FinishingStrategy) -> Relief3DOperation {
    Relief3DOperation(
        setup: OperationSetup(name: "Dome", toolID: ballNose.id),
        params: Relief3DParameters(modelID: model.id, resolution: 0.02,
                                   roughing: RoughingSettings(isEnabled: false),
                                   finishing: FinishingSettings(isEnabled: true, stepover: 0.08, strategy: strategy)))
}

@Test(arguments: [FinishingStrategy.offset, .spiral])
func reliefOffsetFinishingCoversDomeWithoutGouging(strategy: FinishingStrategy) throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let fin = try #require(finishOp(model, strategy: strategy).generate(in: ctx).first)
    #expect(fin.metadata["pass"] == "finishing")
    #expect(ReliefFixture.followsConventions(fin, coords: ctx.coords))
    let samples = ReliefFixture.cutSamples(fin, coords: ctx.coords, step: 0.03)
    let gouge = ReliefFixture.maxGouge(samples, cutter: CutterProfile(tool: ballNose), surface: ReliefFixture.domeDepth,
                                       grid: 0.02)
    #expect(gouge < 0.006)
    // Stays in the footprint, reaches the apex and the base plane.
    for (p, _) in samples { #expect(p.x >= 1 - 1e-6 && p.x <= 3 + 1e-6 && p.y >= 1 - 1e-6 && p.y <= 3 + 1e-6) }
    #expect(samples.map(\.1).min()! < 0.02)
    #expect(abs(samples.map(\.1).max()! - 1) < 1e-6)
    // Rings run around the centre: the outermost pass follows the boundary square.
    let first = samples.prefix(20).map(\.0)
    #expect(first.allSatisfy { min(abs($0.x - 1), abs($0.x - 3), abs($0.y - 1), abs($0.y - 3)) < 0.01 })
}

@Test func reliefSpiralFinishingRetractsLessThanOffset() throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let offset = try #require(finishOp(model, strategy: .offset).generate(in: ctx).first)
    let spiral = try #require(finishOp(model, strategy: .spiral).generate(in: ctx).first)
    let raster = try #require(finishOp(model, strategy: .raster).generate(in: ctx).first)
    func rapids(_ tp: Toolpath) -> Int { tp.moves.filter(\.isRapid).count }
    #expect(rapids(spiral) <= rapids(offset))
    // The spiral is one continuous cut: a single entry and the final retract.
    #expect(rapids(spiral) <= 4)
    #expect(offset.moves != raster.moves)
}

@Test func reliefSpiralPathBlendsBetweenRings() {
    let outer = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 4), Vec2(0, 4)]
    let inner = [Vec2(1, 1), Vec2(3, 1), Vec2(3, 3), Vec2(1, 3)]
    let path = ReliefFinishing.spiralPath([outer, inner], from: .zero, step: 0.1, tolerance: 1e-4)
    #expect(path.first == Vec2(0, 0))
    #expect(path.last == Vec2(1, 1))
    // Distance from the centre shrinks monotonically (up to sampling) during the blended lap.
    let centre = Vec2(2, 2)
    let cheb = path.map { max(abs($0.x - centre.x), abs($0.y - centre.y)) }
    #expect(cheb.first! == 2)
    #expect(zip(cheb, cheb.dropFirst()).allSatisfy { $1 <= $0 + 1e-9 })
}
