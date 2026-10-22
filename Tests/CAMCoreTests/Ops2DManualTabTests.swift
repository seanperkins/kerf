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

private func tabbedProfile(_ paths: [Path], shapes: ((UUID) -> [Int])? = nil, tabs: ([UUID]) -> TabSettings,
                           side: ProfileSide = .outside, tune: (inout ProfileParameters) -> Void = { _ in }) throws -> (Toolpath, CAMContext, [UUID]) {
    let (ctx, ids) = F.document(paths)
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: side)
    p.tabs = tabs(ids)
    tune(&p)
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: [ids[0]]), params: p)
    return (try op.generate(in: ctx)[0], ctx, ids)
}

@Test func ops2DProfileWarnsWhenALoopIsTooShortForTheRequestedTabs() throws {
    // A 0.3 in square cut outside with a 1/4 in end mill: the loop is about 2 in around, and
    // four 1/4 in tabs need 4 in of loop to stay apart, so one fits. The job must still post,
    // and the operator must be told the part is held by one tab, not four.
    let (tp, ctx, _) = try tabbedProfile([F.rect(0, 0, 0.3, 0.3)]) { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
    }
    #expect(!tp.moves.isEmpty)
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == 1)
    let w = try #require(tp.metadata["warning"])
    #expect(w.contains("1 loop(s) too short for the tabs asked") && w.contains("fewest placed: 1"))
    // A loop long enough for its tabs says nothing.
    let (tp2, _, _) = try tabbedProfile([F.rect(0, 0, 6, 4)]) { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
    }
    #expect(tp2.metadata["warning"] == nil)
}

@Test func ops2DProfileIgnoresAnchorsOnOtherVectorsAndSaysSo() throws {
    // One anchor sits on a neighbouring part 0.3 in away that this toolpath does not cut, one on
    // a vector that was deleted. Neither may be dragged onto this part's loop: no tab is placed,
    // and the warning says why.
    let (tp, ctx, _) = try tabbedProfile([F.rect(0, 0, 6, 4), F.rect(6.3, 0, 2, 2)]) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1,
                    manualTabs: [TabAnchor(shapeID: ids[1], fraction: 0.25), TabAnchor(shapeID: UUID(), fraction: 0.5)])
    }
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).isEmpty)
    let w = try #require(tp.metadata["warning"])
    #expect(w.contains("2 tab anchor(s) ignored") && w.contains("no tab placed"))
    // An anchor on this toolpath's own vector places its tab without a word, with or without a
    // last pass (which resolves the anchors again and must not count them twice).
    for lastPass in [nil, ProfileLastPass(allowance: 0.02)] {
        let (tp2, _, _) = try tabbedProfile([F.rect(0, 0, 6, 4), F.rect(6.3, 0, 2, 2)], tabs: { ids in
            TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15)])
        }, tune: { $0.lastPass = lastPass })
        #expect(tabEntries(tp2, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == (lastPass == nil ? 1 : 2))
        #expect(tp2.metadata["warning"] == nil)
    }
    let (tp3, _, _) = try tabbedProfile([F.rect(0, 0, 6, 4), F.rect(6.3, 0, 2, 2)], tabs: { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[1], fraction: 0.25)])
    }, tune: { $0.lastPass = ProfileLastPass(allowance: 0.02) })
    #expect(tp3.metadata["warning"]?.contains("1 tab anchor(s) ignored") == true)
}

@Test func ops2DProfileOverlappingManualAnchorsAreReportedOnce() throws {
    // Two anchors a hair apart on a 20 in loop merge into one tab; the operator asked for two.
    let (tp, ctx, _) = try tabbedProfile([F.rect(0, 0, 6, 4)], tabs: { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1,
                    manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15), TabAnchor(shapeID: ids[0], fraction: 0.16)])
    }, tune: { $0.lastPass = ProfileLastPass(allowance: 0.02) })
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == 2)   // one tab, rough and last pass
    #expect(tp.metadata["warning"] == "1 overlapping tab anchor(s) merged with a neighbour")
}

@Test func ops2DProfileLaysOutTabsOnTheLastPassWhenRoughingCollapsed() throws {
    // A 0.45 in wide slot cut inside with a 1/4 in tool and a 0.1 in last-pass allowance: the
    // roughing offset (0.225 a side) swallows the loop and only the last pass cuts. It must lay
    // out its own tabs rather than inherit none, and count a dropped anchor.
    let (tp, ctx, _) = try tabbedProfile([F.rect(0, 0, 0.45, 2)], tabs: { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 2)
    }, side: .inside, tune: { $0.lastPass = ProfileLastPass(allowance: 0.1) })
    let c = ctx.coords
    #expect(tabEntries(tp, cut: c.z(depth: 0.5), top: c.z(depth: 0.4)).count == 2)
    #expect(tp.metadata["warning"] == nil)
    let (tp2, _, _) = try tabbedProfile([F.rect(0, 0, 0.45, 2)], tabs: { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: UUID(), fraction: 0.5)])
    }, side: .inside, tune: { $0.lastPass = ProfileLastPass(allowance: 0.1) })
    #expect(tp2.metadata["warning"]?.contains("1 tab anchor(s) ignored") == true)
}

@Test func tabAnchorsOffTheToolpathsShapesAreReturnedNotAttached() throws {
    var doc = Document()
    let near = Shape(layerID: doc.defaultLayerID, paths: [F.rect(0, 0, 4, 2)])
    let far = Shape(layerID: doc.defaultLayerID, paths: [F.rect(10, 0, 4, 2)])
    doc.add(near); doc.add(far)
    let loop = try #require(TabAnchors.chain(near.paths[0], tolerance: 0.001))
    let gone = TabAnchor(shapeID: UUID(), fraction: 0.25)
    let anchors = [TabAnchor(shapeID: near.id, fraction: 0.25), TabAnchor(shapeID: far.id, fraction: 0.25), gone]
    let r = TabAnchors.centers(for: anchors, loops: [loop], shapeIDs: [near.id], document: doc, tolerance: 0.001)
    #expect(r.centers == [[3]] && r.ignored == [anchors[1], gone])
    // A shape the toolpath cuts may be far from the loop (a distant loop of the same operation).
    #expect(TabAnchors.centers(for: anchors, loops: [loop], shapeIDs: [near.id, far.id], document: doc, tolerance: 0.001).ignored == [gone])
}
