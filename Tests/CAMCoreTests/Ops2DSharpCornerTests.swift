import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func cutPoints(side: ProfileSide, sharp: Bool?, paths: [Path]) throws -> [Vec2] {
    let (ctx, ids) = F.document(paths)
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.1), side: side)
    p.sharpCorners = sharp
    let tp = try ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
        .generate(in: ctx)[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    return F.densePoints(tp.moves).filter { $0.z < -1e-9 }.map(\.xy)
}

@Test func ops2DSharpCornersOutsideGoesToTheSquareCorner() throws {
    let rect = Rect2(x: 2, y: 2, width: 4, height: 3)
    let pts = try cutPoints(side: .outside, sharp: true, paths: [F.rect(2, 2, 4, 3)])
    for q in pts { #expect(F.distanceToRectBoundary(q, rect) >= 0.125 - 1e-4) }
    for c in [Vec2(1.875, 1.875), Vec2(6.125, 1.875), Vec2(6.125, 5.125), Vec2(1.875, 5.125)] {
        #expect(pts.contains { $0.distance(to: c) < 1e-4 })
    }
    // The default rolls round the corner instead.
    let round = try cutPoints(side: .outside, sharp: nil, paths: [F.rect(2, 2, 4, 3)])
    #expect(!round.contains { $0.distance(to: Vec2(1.875, 1.875)) < 0.01 })
}

@Test func ops2DSharpCornersInsideSquaresTheIslandCorners() throws {
    // A frame: the inside cut rolls round the inner island's corners unless sharp.
    let (ctx, ids) = F.document(shapePaths: [F.rect(0, 0, 6, 6), F.rect(2, 2, 2, 2)])
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.1), side: .inside)
    p.sharpCorners = true
    let tp = try ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
        .generate(in: ctx)[0]
    let pts = F.densePoints(tp.moves).filter { $0.z < -1e-9 }.map(\.xy)
    #expect(pts.contains { $0.distance(to: Vec2(1.875, 1.875)) < 1e-4 })
}
