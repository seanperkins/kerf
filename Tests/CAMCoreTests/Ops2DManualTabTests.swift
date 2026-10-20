import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// Points where a pass rises from the cut depth to the tab top.
private func tabEntries(_ tp: Toolpath, cut: Double, top: Double) -> [Vec3] {
    let pts = F.densePoints(tp.moves)
    return zip(pts, pts.dropFirst()).compactMap { a, b in
        abs(a.z - cut) < 1e-9 && abs(b.z - top) < 1e-9 ? b : nil
    }
}

private func profile(_ tabs: (UUID) -> TabSettings) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document([F.rect(0, 0, 6, 4)])
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: .outside)
    p.tabs = tabs(ids[0])
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
    return (try op.generate(in: ctx)[0], ctx)
}

@Test func ops2DProfileManualTabsAreCutWhereAnchored() throws {
    // Perimeter 20, path starts at (0,0) going along the bottom edge: fraction 0.15 → (3, 0).
    let (tp, ctx) = try profile { id in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: id, fraction: 0.15)])
    }
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == 1)
    // The raised section is centred just outside the bottom edge at x = 3.
    let raised = F.densePoints(tp.moves).filter { abs($0.z - c.z(depth: 0.4)) < 1e-9 }
    #expect(!raised.isEmpty)
    let mid = raised.reduce(Vec2.zero) { $0 + $1.xy } * (1 / Double(max(raised.count, 1)))
    #expect(mid.distance(to: c.machineXY(Vec2(3, -0.125))) < 0.05)
}

@Test func ops2DProfileEmptyManualTabListMeansNoTabs() throws {
    let (tp, ctx) = try profile { _ in TabSettings(isEnabled: true, thickness: 0.1, manualTabs: []) }
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).isEmpty)
    #expect(abs(tp.minZ! - c.z(depth: 0.5)) < 1e-9)
}

@Test func tabAnchorsRoundTripThroughPositions() throws {
    var doc = Document()
    let s = Shape(layerID: doc.defaultLayerID, paths: [F.rect(0, 0, 4, 2)])
    doc.add(s)
    let a = try #require(TabAnchors.anchor(nearest: Vec2(2, 2.05), on: [s], maxDistance: 0.1, tolerance: 0.001))
    let p = try #require(TabAnchors.point(of: a, in: doc, tolerance: 0.001))
    #expect(p.distance(to: Vec2(2, 2)) < 1e-6)
    #expect(TabAnchors.anchor(nearest: Vec2(2, 3), on: [s], maxDistance: 0.1, tolerance: 0.001) == nil)
}

@Test func tabAnchorsFollowTheVectorWhenItMoves() throws {
    var doc = Document()
    var s = Shape(layerID: doc.defaultLayerID, paths: [F.rect(0, 0, 4, 2)])
    doc.add(s)
    let a = TabAnchor(shapeID: s.id, fraction: 0.25)
    s = s.transformed(.translation(Vec2(10, 5)))
    doc.shapes[0] = s
    let p = try #require(TabAnchors.point(of: a, in: doc, tolerance: 0.001))
    #expect(p.distance(to: Vec2(13, 5)) < 1e-6)
}

@Test func overlappingManualTabsAreMerged() {
    let layout = TabLayout(loopLength: 20, centers: [5, 5.1, 12, 19.95], settings: TabSettings(length: 0.25, thickness: 0.1),
                           toolDiameter: 0.25, cutDepth: 0.5)
    #expect(layout.centers == [5, 12, 19.95])
}
