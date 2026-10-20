import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func firstCutXY(_ start: ProfileStartPoint?, paths: [Path] = [F.rect(2, 2, 4, 3)]) throws -> Vec2 {
    let (ctx, ids) = F.document(paths)
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.1))
    p.startPoint = start
    let tp = try ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
        .generate(in: ctx)[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    for m in tp.moves { if case .linear(let q, _) = m { return q.xy } }
    Issue.record("no cut")
    return .zero
}

@Test func ops2DStartPointBoundingBoxSides() throws {
    #expect(try firstCutXY(.left).distance(to: Vec2(1.875, 3.5)) < 1e-6)
    #expect(try firstCutXY(.right).distance(to: Vec2(6.125, 3.5)) < 1e-6)
    #expect(try firstCutXY(.bottom).distance(to: Vec2(4, 1.875)) < 1e-6)
    #expect(try firstCutXY(.top).distance(to: Vec2(4, 5.125)) < 1e-6)
}

@Test func ops2DStartPointVectorStartNode() throws {
    // A rectangle drawn starting at its upper-right corner.
    let path = Path(points: [Vec2(6, 5), Vec2(2, 5), Vec2(2, 2), Vec2(6, 2)], closed: true)
    let q = try firstCutXY(.vectorStart, paths: [path])
    #expect(abs(q.distance(to: Vec2(6, 5)) - 0.125) < 0.001)
    // The default starts nearest the home position (lower-left), not at the start node.
    let d = try firstCutXY(nil, paths: [path])
    #expect(d.distance(to: Vec2(2, 2)) < 0.2)
}
