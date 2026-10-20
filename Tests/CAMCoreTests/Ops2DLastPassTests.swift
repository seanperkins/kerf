import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func lastPassProfile(side: ProfileSide = .outside, lastPass: ProfileLastPass?,
                             zZero: ZZeroMode = .materialTop) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document([F.rect(2, 2, 4, 3)], zZero: zZero)
    let p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: side, lastPass: lastPass)
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
    let tps = try op.generate(in: ctx)
    return (tps[0], ctx)
}

/// Cut points with their distance to the rectangle boundary, in move order.
private func distances(_ tp: Toolpath, coords: MachineCoordinates) -> [(d: Double, depth: Double, xy: Vec2)] {
    let rect = Rect2(x: 2, y: 2, width: 4, height: 3)
    return F.densePoints(tp.moves).map { p in
        (F.distanceToRectBoundary(p.xy, rect), coords.depth(ofMachineZ: p.z), p.xy)
    }.filter { $0.depth > 1e-9 }
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DLastPassRoughingLeavesAllowanceThenFinishesAtFullDepth(mode: ZZeroMode) throws {
    let (tp, ctx) = try lastPassProfile(lastPass: ProfileLastPass(allowance: 0.02), zZero: mode)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let pts = distances(tp, coords: ctx.coords)
    let rough = pts.filter { abs($0.d - 0.145) < 0.0011 }
    let finish = pts.filter { abs($0.d - 0.125) < 0.0011 }
    #expect(!rough.isEmpty && !finish.isEmpty)
    #expect(rough.count + finish.count == pts.count)
    // Roughing reaches the full depth in passes; the finish lap is one pass at the cut depth.
    #expect(abs(rough.map(\.depth).max()! - 0.5) < 1e-9)
    #expect(finish.allSatisfy { abs($0.depth - 0.5) < 1e-9 })
    // Finish comes after all roughing.
    let lastRough = pts.lastIndex { abs($0.d - 0.145) < 0.0011 }!
    let firstFinish = pts.firstIndex { abs($0.d - 0.125) < 0.0011 }!
    #expect(lastRough < firstFinish)
}

@Test func ops2DLastPassReverseDirectionFlipsTheFinishLoop() throws {
    func finishArea(_ reverse: Bool) throws -> Double {
        let (tp, ctx) = try lastPassProfile(lastPass: ProfileLastPass(allowance: 0.02, reverseDirection: reverse))
        let loop = distances(tp, coords: ctx.coords).filter { abs($0.d - 0.125) < 0.0011 }.map(\.xy)
        return Polygon2D.signedArea(loop)
    }
    // Outside + climb = clockwise; reversed = counter-clockwise.
    #expect(try finishArea(false) < 0)
    #expect(try finishArea(true) > 0)
}

@Test func ops2DLastPassFollowsDepthPassesWhenNotFullDepth() throws {
    let (tp, ctx) = try lastPassProfile(side: .inside, lastPass: ProfileLastPass(allowance: 0.02, fullDepth: false))
    let finishDepths = Set(distances(tp, coords: ctx.coords).filter { abs($0.d - 0.125) < 0.0011 }
        .map { ($0.depth * 1000).rounded() })
    #expect(finishDepths == [125, 250, 375, 500])
}

@Test func ops2DLastPassIgnoredWhenCuttingOnTheLine() throws {
    let (on, _) = try lastPassProfile(side: .on, lastPass: ProfileLastPass(allowance: 0.02))
    let (plain, _) = try lastPassProfile(side: .on, lastPass: nil)
    #expect(on.moves == plain.moves)
}

@Test func ops2DLastPassDecodesOldFilesWithoutTheField() throws {
    let data = try JSONEncoder().encode(ProfileParameters())
    var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    obj.removeValue(forKey: "lastPass")
    let back = try JSONDecoder().decode(ProfileParameters.self, from: JSONSerialization.data(withJSONObject: obj))
    #expect(back.lastPass == nil)
}
