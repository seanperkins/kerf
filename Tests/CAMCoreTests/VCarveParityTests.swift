import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = VCarveFixture

private let halfInchMill = ToolLibrary.seeded.tools[2]   // 1/2" end mill
private let eighthMill = ToolLibrary.seeded.tools[1]     // 1/8" end mill
private let engraver = ToolLibrary.seeded.tools[7]       // 30° engraving, 0.01" tip

// MARK: vc-multi-clearance

@Test func vcarveMultipleClearanceToolsRestMachineLargestFirst() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 3, 2)])
    let params = VCarveParameters(flatDepth: 0.15, flatClearanceToolID: halfInchMill.id,
                                  extraClearanceTools: [VCarveClearanceTool(toolID: eighthMill.id)])
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    #expect(tps.map(\.tool.id) == [halfInchMill.id, eighthMill.id, F.vbit60.id])
    #expect(tps[1].name.hasSuffix("(flat clearance 2)"))
    let coords = ctx.coords
    let flatRadius = 0.15 * F.tan30
    func inset(_ p: Vec2) -> Double { min(p.x, 3 - p.x, p.y, 2 - p.y) }
    // The big tool does the bulk; the small one only works where the big one could not reach.
    let small = F.cutPoints(tps[1], coords: coords)
    #expect(!small.isEmpty)
    for p in small {
        #expect(inset(p.xy) > flatRadius + eighthMill.radius - 2e-3)
        let nearCorner = [Vec2(0, 0), Vec2(3, 0), Vec2(3, 2), Vec2(0, 2)].contains { $0.distance(to: p.xy) < 0.6 }
        #expect(nearCorner, "small tool cut away from the corners at \(p.xy)")
    }
    // The corner the big tool rounds over is reached by the small tool.
    let corner = Vec2(flatRadius + eighthMill.radius, flatRadius + eighthMill.radius)
    #expect(small.contains { $0.xy.distance(to: corner) < 0.02 && $0.depth > 0.15 - 1e-6 })
    for tp in tps { F.expectSafeMotion(tp, coords: coords) }
}

@Test func vcarveLaterClearanceToolWithNothingLeftIsSkippedWithWarning() throws {
    let (ctx, setup) = F.context([F.rect(0, 0, 3, 2)])
    let params = VCarveParameters(flatDepth: 0.15, flatClearanceToolID: eighthMill.id,
                                  extraClearanceTools: [VCarveClearanceTool(toolID: halfInchMill.id)])
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    #expect(tps.map(\.tool.id) == [eighthMill.id, F.vbit60.id])
    #expect(tps[0].metadata["warning"]?.contains("no remaining flat area") == true)
}

@Test func vcarveParametersDecodeWithoutNewFields() throws {
    let old = try JSONEncoder().encode(VCarveParameters(flatDepth: 0.1))
    var dict = try #require(try JSONSerialization.jsonObject(with: old) as? [String: Any])
    dict.removeValue(forKey: "extraClearanceTools")
    let p = try JSONDecoder().decode(VCarveParameters.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(p.extraClearanceTools.isEmpty)
    #expect(p.flatDepth == 0.1)
    let round = try JSONDecoder().decode(VCarveParameters.self, from: JSONEncoder().encode(
        VCarveParameters(flatClearanceToolID: halfInchMill.id, extraClearanceTools: [VCarveClearanceTool(toolID: eighthMill.id)])))
    #expect(round.clearanceTools.map(\.toolID) == [halfInchMill.id, eighthMill.id])
}
