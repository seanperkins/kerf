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

// MARK: vc-corner-sharpen

/// 90° engraving tool with a 0.02" tip (wider taper than the 60° V-bit).
private let wideEngraver = Tool(name: "90° engraver", kind: .engraving, number: 20, diameter: 0.5, flutes: 2,
                                angle: 90, tipDiameter: 0.02, stepdown: 0.25, stepover: 0.015,
                                spindleRPM: 18000, feedRate: 60, plungeRate: 20)

private func sharpenContext() -> (CAMContext, OperationSetup) {
    var (ctx, setup) = F.context([F.rect(0, 0, 2, 1)])
    ctx.tools.upsert(wideEngraver)
    return (ctx, setup)
}

@Test(arguments: [false, true])
func vcarveCornerSharpenLiftsEngraverIntoCorners(sharpen: Bool) throws {
    let (ctx, setup) = sharpenContext()
    let params = VCarveParameters(flatDepth: 0.2, flatClearanceToolID: halfInchMill.id,
                                  extraClearanceTools: [VCarveClearanceTool(toolID: wideEngraver.id, cornerSharpen: sharpen)])
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    // The 1/2" mill leaves corner fillets the engraver cannot reach at the full depth, so without
    // sharpening it has nothing to do.
    guard sharpen else {
        #expect(tps.map(\.tool.id) == [halfInchMill.id, F.vbit60.id])
        return
    }
    #expect(tps.map(\.tool.id) == [halfInchMill.id, wideEngraver.id, F.vbit60.id])
    let pts = F.cutPoints(tps[1], coords: ctx.coords)
    // On the corner bisector, inside the fillet the mill left: lifted to R − tip radius.
    let near = pts.filter { $0.xy.distance(to: Vec2(0.14, 0.14)) < 0.01 }
    #expect(!near.isEmpty)
    #expect(near.allSatisfy { abs($0.depth - (0.14 - 0.01)) < 0.015 })
    // The cone never reaches past the V walls: depth ≤ (R − tip radius) / max(tan 45°, tan 30°).
    for p in pts {
        let r = min(p.xy.x, 2 - p.xy.x, p.xy.y, 1 - p.xy.y)
        #expect(p.depth <= r - 0.01 + 2e-3)
        #expect(p.depth <= 0.2 + 1e-6)
    }
    F.expectSafeMotion(tps[1], coords: ctx.coords)
}

@Test func vcarveClearanceToolDecodesWithoutCornerSharpen() throws {
    let json = #"{"toolID":"00000000-0000-4000-8000-000000000002"}"#
    let t = try JSONDecoder().decode(VCarveClearanceTool.self, from: Data(json.utf8))
    #expect(!t.cornerSharpen)
}
