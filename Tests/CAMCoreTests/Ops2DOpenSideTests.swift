import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func openProfile(_ pts: [Vec2], side: OpenVectorSide?) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document([Path(points: pts, closed: false)])
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.25), side: .outside)
    p.openVectorSide = side
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
    return (try op.generate(in: ctx)[0], ctx)
}

@Test func ops2DOpenOffsetStraightLineLeftAndRight() throws {
    let line = [Vec2(0, 0), Vec2(4, 0)]
    let left = try #require(OpenOffset.oneSided(line, distance: 0.125, left: true, tolerance: 0.0005))
    #expect(left.first!.distance(to: Vec2(0, 0.125)) < 1e-6)
    #expect(left.last!.distance(to: Vec2(4, 0.125)) < 1e-6)
    #expect(left.allSatisfy { abs($0.y - 0.125) < 1e-6 })
    let right = try #require(OpenOffset.oneSided(line, distance: 0.125, left: false, tolerance: 0.0005))
    #expect(right.first!.distance(to: Vec2(0, -0.125)) < 1e-6)
    #expect(right.allSatisfy { abs($0.y + 0.125) < 1e-6 })
}

@Test(arguments: [OpenVectorSide.left, .right])
func ops2DProfileOpenVectorKeepsTheToolOnOneSide(side: OpenVectorSide) throws {
    // An L: along +x, then up +y. Left of travel is the inside of the turn.
    let pts = [Vec2(1, 1), Vec2(5, 1), Vec2(5, 4)]
    let (tp, ctx) = try openProfile(pts, side: side)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(tp.metadata["warning"] == nil)
    let chain = ArcLengthChain(Chain2D(points: pts, isClosed: false))
    let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    #expect(!cut.isEmpty)
    for q in cut {
        #expect(abs(chain.project(q.xy).distance - 0.125) < 0.0011)
        // Inside the turn: x < 5 and y > 1; outside: x > 5 or y < 1.
        let insideTurn = q.xy.x < 5 && q.xy.y > 1
        #expect(insideTurn == (side == .left))
    }
}

@Test func ops2DProfileOpenVectorDefaultStaysOnTheLine() throws {
    let pts = [Vec2(1, 1), Vec2(5, 1)]
    let (tp, ctx) = try openProfile(pts, side: nil)
    for q in F.densePoints(tp.moves) where ctx.coords.depth(ofMachineZ: q.z) > 1e-9 {
        #expect(abs(q.xy.y - 1) < 1e-9)
    }
    #expect(tp.metadata["warning"]?.contains("on the line") == true)
}
