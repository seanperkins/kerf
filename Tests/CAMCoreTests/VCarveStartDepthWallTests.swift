import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = VCarveFixture

private let halfInchMill = ToolLibrary.seeded.tools[2]   // 1/2" end mill

/// 90° engraving tool with a 0.02" tip: a wider taper than the 60° V-bit.
private let wideEngraver = Tool(name: "90° engraver", kind: .engraving, number: 20, diameter: 0.5, flutes: 2,
                                angle: 90, tipDiameter: 0.02, stepdown: 0.25, stepover: 0.05,
                                spindleRPM: 18000, feedRate: 60, plungeRate: 20)

/// Issue #96. With a start depth the V-bit's cone keeps widening above it, so the wall it leaves reaches the
/// surface `startDepth * tan(half angle)` OUTSIDE the vector. A clearance tool with a wider taper than the V-bit
/// has to stay out of that flared wall, not only out of the part of it below the start depth.
private struct RectWall {
    var w: Double, h: Double
    var startDepth: Double
    var floor: Double
    var slope: Double

    /// Distance from the rectangle's outline: positive inside, negative outside.
    func signedDistance(_ q: Vec2) -> Double {
        let dx = max(-q.x, 0, q.x - w), dy = max(-q.y, 0, q.y - h)
        let outside = (dx * dx + dy * dy).squareRoot()
        return outside > 0 ? -outside : min(q.x, w - q.x, q.y, h - q.y)
    }

    /// Depth of the carved surface at `q`; material is left below it.
    func depth(at q: Vec2) -> Double { min(floor, max(0, startDepth + signedDistance(q) / slope)) }

    /// How far below the wall `tool`, with its tip at `tip` (xy, depth), reaches. Positive is material it should not touch.
    func gouge(of tool: Tool, tip: (xy: Vec2, depth: Double)) -> Double {
        let slopeT = tan((tool.angle ?? 90) / 2 * .pi / 180)
        let rt = tool.tipDiameter / 2, radius = tool.radius
        var worst = -Double.infinity
        let step = 0.004
        var dx = -radius
        while dx <= radius {
            var dy = -radius
            while dy <= radius {
                let d = (dx * dx + dy * dy).squareRoot()
                if d <= radius {
                    let q = tip.xy + Vec2(dx, dy)
                    worst = max(worst, tip.depth - max(0, d - rt) / slopeT - depth(at: q))
                }
                dy += step
            }
            dx += step
        }
        return worst
    }

    /// The `count` cut points closest to the outline: the ones that can reach the wall.
    func nearest(_ pts: [(xy: Vec2, depth: Double)], _ count: Int) -> [(xy: Vec2, depth: Double)] {
        Array(pts.sorted { signedDistance($0.xy) < signedDistance($1.xy) }.prefix(count))
    }
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func vcarveCornerSharpenStaysOffTheFlaredWallWhenCarvingFromADepth(zZero: ZZeroMode) throws {
    var (ctx, setup) = F.context([F.rect(0, 0, 2, 1)], zZero: zZero)
    ctx.tools.upsert(wideEngraver)
    let params = VCarveParameters(startDepth: 0.1, flatDepth: 0.2, flatClearanceToolID: halfInchMill.id,
                                  extraClearanceTools: [VCarveClearanceTool(toolID: wideEngraver.id, cornerSharpen: true)])
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    #expect(tps.map(\.tool.id) == [halfInchMill.id, wideEngraver.id, F.vbit60.id])
    let pts = F.cutPoints(tps[1], coords: ctx.coords)
    #expect(!pts.isEmpty)
    let wall = RectWall(w: 2, h: 1, startDepth: 0.1, floor: 0.3, slope: F.tan30)
    let worst = wall.nearest(pts, 60).map { wall.gouge(of: wideEngraver, tip: $0) }.max() ?? 0
    #expect(worst < 0.006, "the sharpening cone cuts \(worst) in into the V wall")
    F.expectSafeMotion(tps[1], coords: ctx.coords)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func vcarveTaperedFlatClearanceToolStaysOffTheFlaredWallWhenCarvingFromADepth(zZero: ZZeroMode) throws {
    var (ctx, setup) = F.context([F.rect(0, 0, 1, 0.6)], zZero: zZero)
    ctx.tools.upsert(wideEngraver)
    let params = VCarveParameters(startDepth: 0.1, flatDepth: 0.1, flatClearanceToolID: wideEngraver.id)
    let tps = try VCarveOperation(setup: setup, params: params).generate(in: ctx)
    #expect(tps.map(\.tool.id) == [wideEngraver.id, F.vbit60.id])
    let pts = F.cutPoints(tps[0], coords: ctx.coords)
    #expect(!pts.isEmpty)
    let wall = RectWall(w: 1, h: 0.6, startDepth: 0.1, floor: 0.2, slope: F.tan30)
    let worst = wall.nearest(pts, 60).map { wall.gouge(of: wideEngraver, tip: $0) }.max() ?? 0
    #expect(worst < 0.006, "the clearance cone cuts \(worst) in into the V wall")
    F.expectSafeMotion(tps[0], coords: ctx.coords)
}

/// The start depth only matters to a tool whose taper is wider than the V-bit's: a narrower one, and the
/// no-start-depth case, keep the clearance they always had.
@Test func vcarveWallClearanceIsUnchangedWithoutAStartDepthOrAWiderTaper() {
    let narrow = Tool(name: "20° engraver", kind: .engraving, number: 21, diameter: 0.25, angle: 20, tipDiameter: 0.02,
                      stepdown: 0.05, stepover: 0.01, feedRate: 40, plungeRate: 10)
    let tV = F.tan30
    // Wider taper, no start depth: tip radius + the tip's depth * (tT - tV), as before.
    #expect(abs(VCarveEngine.wallClearance(of: wideEngraver, tipDepth: 0.1, vSlope: tV)
                - (0.01 + 0.1 * (1 - tV))) < 1e-12)
    // With a start depth the tip is that much deeper below the surface, and the cone is lowered with it.
    #expect(abs(VCarveEngine.wallClearance(of: wideEngraver, tipDepth: 0.2, vSlope: tV)
                - (0.01 + 0.2 * (1 - tV))) < 1e-12)
    // A taper narrower than the V-bit gains nothing on the wall, whatever the start depth.
    #expect(abs(VCarveEngine.wallClearance(of: narrow, tipDepth: 0.4, vSlope: tV) - 0.01) < 1e-12)
    // A cylindrical tool is its radius.
    #expect(VCarveEngine.wallClearance(of: halfInchMill, tipDepth: 0.4, vSlope: tV) == 0.25)
}
