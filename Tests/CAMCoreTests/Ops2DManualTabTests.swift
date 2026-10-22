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

// MARK: - Tabs that could not be placed as asked are reported (issue #9)

@Test func ops2DProfileWarnsWhenALoopIsTooShortForTheRequestedTabs() throws {
    // A 0.3 in square cut outside with a 1/4 in end mill: the loop is about 2 in around, and
    // four 1/4 in tabs need 4 in of loop to stay apart, so one fits. The job must still post,
    // and the operator must be told the part is held by one tab, not four.
    let (ctx, ids) = F.document([F.rect(0, 0, 0.3, 0.3)])
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: .outside)
    p.tabs = TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids), params: p)
    let tp = try op.generate(in: ctx)[0]
    #expect(!tp.moves.isEmpty)
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == 1)
    let w = try #require(tp.metadata["warning"])
    #expect(w.contains("tabs") && w.contains("4 asked") && w.contains("1 fit"))
    // A loop long enough for its tabs says nothing.
    let (ctx2, ids2) = F.document([F.rect(0, 0, 6, 4)])
    let op2 = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids2), params: p)
    #expect(try op2.generate(in: ctx2)[0].metadata["warning"] == nil)
}

@Test func ops2DProfileIgnoresAnchorsFarFromItsVectorsAndSaysSo() throws {
    // The anchor sits on another part 5 in away (or on a vector that was deleted). It must not be
    // dragged onto the nearest loop of this toolpath: no tab is placed, and the warning says why.
    let (ctx, ids) = F.document([F.rect(0, 0, 6, 4), F.rect(11, 0, 2, 2)])
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: .outside)
    p.tabs = TabSettings(isEnabled: true, length: 0.25, thickness: 0.1,
                         manualTabs: [TabAnchor(shapeID: ids[1], fraction: 0.25), TabAnchor(shapeID: UUID(), fraction: 0.5)])
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: [ids[0]]), params: p)
    let tp = try op.generate(in: ctx)[0]
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).isEmpty)
    let w = try #require(tp.metadata["warning"])
    #expect(w.contains("2 tab anchor(s) ignored") && w.contains("no tab was placed"))
    // An anchor on this toolpath's own vector is within reach and places its tab without a word.
    p.tabs.manualTabs = [TabAnchor(shapeID: ids[0], fraction: 0.15)]
    let op2 = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: [ids[0]]), params: p)
    let tp2 = try op2.generate(in: ctx)[0]
    #expect(tabEntries(tp2, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == 1)
    #expect(tp2.metadata["warning"] == nil)
}

@Test func tabAnchorsBeyondReachAreCountedNotAttached() throws {
    var doc = Document()
    let near = Shape(layerID: doc.defaultLayerID, paths: [F.rect(0, 0, 4, 2)])
    let far = Shape(layerID: doc.defaultLayerID, paths: [F.rect(10, 0, 4, 2)])
    doc.add(near); doc.add(far)
    let loop = try #require(TabAnchors.chain(near.paths[0], tolerance: 0.001))
    let anchors = [TabAnchor(shapeID: near.id, fraction: 0.25), TabAnchor(shapeID: far.id, fraction: 0.25),
                   TabAnchor(shapeID: UUID(), fraction: 0.25)]
    let r = TabAnchors.centers(for: anchors, loops: [loop], document: doc, maxDistance: 0.5, tolerance: 0.001)
    #expect(r.centers == [[3]] && r.ignored == 2)
    // With no limit to speak of, the far anchor lands on the only loop, as before.
    #expect(TabAnchors.centers(for: anchors, loops: [loop], document: doc, maxDistance: 100, tolerance: 0.001).ignored == 1)
}
