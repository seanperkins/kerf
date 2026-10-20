import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// Indices (in cut order) of interior raster segments and of long wall segments along X = const.
private func segmentOrder(first: Bool?) throws -> (raster: [Int], wall: [Int]) {
    let (ctx, ids) = F.document([F.rect(0, 0, 4, 3)])
    var p = PocketParameters(depth: DepthSettings(cutDepth: 0.1), strategy: .raster(angle: 0, profilePass: true))
    p.profilePassFirst = first
    let tp = try PocketOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
        .generate(in: ctx)[0]
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let pts = F.densePoints(tp.moves).filter { $0.z < -1e-9 }.map(\.xy)
    var raster: [Int] = [], wall: [Int] = []
    for (i, (a, b)) in zip(pts, pts.dropFirst()).enumerated() {
        if abs(a.y - b.y) < 1e-9, a.distance(to: b) > 3, a.y > 0.2, a.y < 2.8 { raster.append(i) }
        if abs(a.x - b.x) < 1e-9, a.distance(to: b) > 2 { wall.append(i) }
    }
    return (raster, wall)
}

@Test func ops2DPocketProfilePassFirstCutsTheWallBeforeTheRaster() throws {
    let first = try segmentOrder(first: true)
    #expect(!first.raster.isEmpty && !first.wall.isEmpty)
    #expect(first.wall.max()! < first.raster.min()!)
    let last = try segmentOrder(first: nil)
    #expect(last.wall.min()! > last.raster.max()!)
}
