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

// MARK: vc-inlay-boundary-options

private func plug(_ params: InlayParameters, _ paths: [Path] = [F.rect(4, 4, 1, 1)]) throws -> (Toolpath, CAMContext) {
    var p = params
    p.part = .male
    var (ctx, setup) = F.context(paths)
    ctx.document.job.width = 7     // small sheet keeps the sheet-limits plug quick
    ctx.document.job.height = 6
    let tps = try InlayOperation(setup: setup, params: p).generate(in: ctx)
    return (try #require(tps.last), ctx)
}

@Test func inlayPlugBoundaryVectorOffsetHugsTheOutline() throws {
    // A diamond: its bounding box corners are far from the outline.
    let diamond = Path(points: [Vec2(5, 4), Vec2(6, 5), Vec2(5, 6), Vec2(4, 5)], closed: true)
    let (box, ctx) = try plug(InlayParameters(maleBoundaryMargin: 0.2), [diamond])
    let (hug, _) = try plug(InlayParameters(maleBoundaryMargin: 0.2, plugBoundary: .vectorOffset), [diamond])
    let corner = Vec2(4.0, 4.0)   // bounding-box corner, 0.707 from the diamond
    #expect(F.removedDepth(at: corner, by: F.cutPoints(box, coords: ctx.coords), slope: F.tan30) > 0.05)
    #expect(F.removedDepth(at: corner, by: F.cutPoints(hug, coords: ctx.coords), slope: F.tan30) == 0)
    // Every vector-offset cut stays within margin of the diamond (|dx| + |dy| ≤ 1 + margin·√2).
    for p in F.cutPoints(hug, coords: ctx.coords) {
        #expect(abs(p.xy.x - 5) + abs(p.xy.y - 5) <= 1 + 0.2 * 2.0.squareRoot() + 2e-3)
    }
    F.expectSafeMotion(hug, coords: ctx.coords)
}

@Test func inlayPlugBoundarySheetLimitsClearsToTheMaterialEdge() throws {
    let (tp, ctx) = try plug(InlayParameters(maleBoundaryMargin: 0.2, plugBoundary: .sheetLimits))
    let b = tp.xyBounds
    let job = ctx.document.job
    let shift = job.originInMaterialFrame
    #expect(b.min.x < 0.1 - shift.x && b.max.x > job.width - 0.1 - shift.x)
    #expect(b.min.y < 0.1 - shift.y && b.max.y > job.height - 0.1 - shift.y)
}

@Test func inlaySurfaceClearanceSetsPlugCarveDepth() throws {
    let base = InlayParameters(pocketDepth: 0.2, maleStartDepth: 0.1, glueGap: 0.02, surfaceClearance: 0.05)
    let (tp, ctx) = try plug(base)
    let depths = F.cutPoints(tp, coords: ctx.coords).map(\.depth)
    #expect(abs((depths.max() ?? 0) - 0.15) < 1e-6)
    #expect(tp.metadata["boardGap"] == "0.0500")
    #expect(tp.metadata["bottomGap"] == "0.1000")
    var bad = base
    bad.surfaceClearance = 0
    #expect(throws: CAMError.self) { try plug(bad) }
    bad.surfaceClearance = 2   // thicker than the 0.75" material
    #expect(throws: CAMError.self) { try plug(bad) }
}

@Test func inlayParametersDecodeWithoutBoundaryFields() throws {
    let data = try JSONEncoder().encode(InlayParameters())
    var dict = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    for k in ["plugBoundary", "surfaceClearance", "extraClearanceTools"] { dict.removeValue(forKey: k) }
    let p = try JSONDecoder().decode(InlayParameters.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(p.plugBoundary == .boundaryOffset && p.surfaceClearance == nil && p.extraClearanceTools.isEmpty)
}

// MARK: vc-vbit-engrave

private let openLine = Path(points: [Vec2(1, 1), Vec2(3, 1), Vec2(3, 2)], closed: false)

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func vcarveEngravesOpenVectorAtConstantDepth(zZero: ZZeroMode) throws {
    let (ctx, setup) = F.context([openLine], zZero: zZero)
    let tps = try VCarveOperation(setup: setup, params: VCarveParameters(startDepth: 0.02, openVectorDepth: 0.05))
        .generate(in: ctx)
    #expect(tps.count == 1)
    let tp = try #require(tps.first)
    let pts = F.cutPoints(tp, coords: ctx.coords)
    // Feed moves at depth follow the line (plunge included), all at start + depth.
    let atDepth = pts.filter { abs($0.depth - 0.07) < 1e-6 }
    #expect(atDepth.count > 100)
    for p in atDepth {
        let onLine = (abs(p.xy.y - 1) < 1e-6 && p.xy.x >= 1 - 1e-6 && p.xy.x <= 3 + 1e-6)
            || (abs(p.xy.x - 3) < 1e-6 && p.xy.y >= 1 - 1e-6 && p.xy.y <= 2 + 1e-6)
        #expect(onLine)
    }
    #expect(pts.allSatisfy { $0.depth <= 0.07 + 1e-6 })
    #expect(tp.metadata["warning"] == nil)
    F.expectSafeMotion(tp, coords: ctx.coords)
}

@Test func vcarveEngravesOpenVectorWithTaperedEnds() throws {
    let (ctx, setup) = F.context([openLine])
    let params = VCarveParameters(openVectorDepth: 0.1, openVectorTaper: 0.25)
    let tp = try #require(try VCarveOperation(setup: setup, params: params).generate(in: ctx).first)
    let pts = F.cutPoints(tp, coords: ctx.coords).filter { $0.depth > 1e-9 }
    func depth(near q: Vec2) -> Double { pts.filter { $0.xy.distance(to: q) < 0.02 }.map(\.depth).max() ?? -1 }
    // Length 3: the first and last 0.75 ease in; the middle is at full depth.
    #expect(depth(near: Vec2(1.02, 1)) < 0.01)
    #expect(abs(depth(near: Vec2(1.375, 1)) - 0.05) < 0.01)
    #expect(abs(depth(near: Vec2(2.5, 1)) - 0.1) < 1e-3)
    #expect(depth(near: Vec2(3, 1.98)) < 0.01)
}

@Test func vcarveMixesClosedCarvingAndOpenEngraving() throws {
    let (ctx, setup) = F.context([F.rect(5, 5, 0.4, 0.3), openLine])
    let ignored = try #require(try VCarveOperation(setup: setup).generate(in: ctx).first)
    #expect(ignored.metadata["warning"]?.contains("1 open vector(s) ignored") == true)
    let tp = try #require(try VCarveOperation(setup: setup, params: VCarveParameters(openVectorDepth: 0.05))
        .generate(in: ctx).first)
    #expect(tp.metadata["warning"] == nil)
    let pts = F.cutPoints(tp, coords: ctx.coords)
    #expect(pts.contains { $0.xy.distance(to: Vec2(2, 1)) < 0.01 && abs($0.depth - 0.05) < 1e-6 })
    #expect(pts.contains { $0.xy.x > 5 && abs($0.depth - 0.15 / F.tan30) < 1e-3 })
}

@Test func vcarveClearanceToolDecodesWithoutCornerSharpen() throws {
    let json = #"{"toolID":"00000000-0000-4000-8000-000000000002"}"#
    let t = try JSONDecoder().decode(VCarveClearanceTool.self, from: Data(json.utf8))
    #expect(!t.cornerSharpen)
}
