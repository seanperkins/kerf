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

private let quarterTabs = TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 2)

/// A profile over `paths` (the first is always selected; `select` adds more by index), 0.5 in
/// deep with the 1/4 in end mill. Returns the toolpath and its context.
private func tabbedProfile(_ paths: [Path], select: [Int] = [], side: ProfileSide = .outside,
                           lastPass: ProfileLastPass? = nil, tabs: ([UUID]) -> TabSettings) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document(paths)
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: side)
    p.tabs = tabs(ids)
    p.lastPass = lastPass
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: [ids[0]] + select.map { ids[$0] }), params: p)
    return (try op.generate(in: ctx)[0], ctx)
}

private func tabCount(_ tp: Toolpath, _ ctx: CAMContext) -> Int {
    tabEntries(tp, cut: ctx.coords.z(depth: 0.5), top: ctx.coords.z(depth: 0.4)).count
}

private let fewerTabs = "loop(s) got fewer tabs than asked"
private let ignoredAnchors = "tab anchor(s) ignored"

private func noTabWarning(_ tp: Toolpath) -> Bool {
    let w = tp.metadata["warning"] ?? ""
    return !w.contains(fewerTabs) && !w.contains(ignoredAnchors)
}

@Test func ops2DProfileWarnsWhenALoopIsTooShortForTheRequestedTabs() throws {
    // A 0.3 in square cut outside with a 1/4 in end mill: the loop is about 2 in around, and
    // four 1/4 in tabs need 4 in of loop to stay apart, so one fits. The job must still post,
    // and the operator must be told the part is held by one tab, not four.
    let (tp, ctx) = try tabbedProfile([F.rect(0, 0, 0.3, 0.3)]) { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
    }
    #expect(!tp.moves.isEmpty && tabCount(tp, ctx) == 1)
    let w = try #require(tp.metadata["warning"])
    #expect(w.contains("1 \(fewerTabs)") && w.contains("fewest placed: 1"))
    // A loop long enough for its tabs says nothing.
    let (tp2, _) = try tabbedProfile([F.rect(0, 0, 6, 4)]) { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
    }
    #expect(tp2.metadata["warning"] == nil)
}

@Test func ops2DProfileIgnoresAnchorsOffItsOwnClosedVectorsAndSaysSo() throws {
    // Anchors that must not be dragged onto this part's loop: on a neighbouring part 0.3 in away
    // that this toolpath does not cut, on a deleted vector, on a selected open vector, and on a
    // selected vector the tool cannot enter (its loop is gone). No tab is placed for any of them.
    let line = Path(points: [Vec2(0, 4.5), Vec2(4, 4.5)], closed: false)
    let cases: [(String, [Path], [Int], ProfileSide, ([UUID]) -> [TabAnchor])] = [
        ("neighbour", [F.rect(0, 0, 6, 4), F.rect(6.3, 0, 2, 2)], [], .outside, { [TabAnchor(shapeID: $0[1], fraction: 0.25)] }),
        ("deleted", [F.rect(0, 0, 6, 4)], [], .outside, { _ in [TabAnchor(shapeID: UUID(), fraction: 0.5)] }),
        ("open vector", [F.rect(0, 0, 6, 4), line], [1], .outside, { [TabAnchor(shapeID: $0[1], fraction: 0.5)] }),
        ("swallowed vector", [F.rect(0, 0, 6, 4), F.rect(7, 0, 0.2, 1)], [1], .inside, { [TabAnchor(shapeID: $0[1], fraction: 0.25)] }),
    ]
    for (name, paths, select, side, anchors) in cases {
        let (tp, ctx) = try tabbedProfile(paths, select: select, side: side) { ids in
            TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: anchors(ids))
        }
        #expect(tabCount(tp, ctx) == 0, "\(name)")
        #expect(tp.metadata["warning"]?.contains("1 \(ignoredAnchors)") == true, "\(name): \(tp.metadata["warning"] ?? "nil")")
    }
    // An anchor on this toolpath's own vector places its tab without a word, with or without a
    // last pass, which resolves the anchors again and must not count them twice.
    for lastPass in [nil, ProfileLastPass(allowance: 0.02)] {
        let (tp, ctx) = try tabbedProfile([F.rect(0, 0, 6, 4), F.rect(6.3, 0, 2, 2)], lastPass: lastPass) { ids in
            TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15)])
        }
        #expect(tabCount(tp, ctx) == (lastPass == nil ? 1 : 2))
        #expect(tp.metadata["warning"] == nil)
    }
    let (tp3, _) = try tabbedProfile([F.rect(0, 0, 6, 4), F.rect(6.3, 0, 2, 2)], lastPass: ProfileLastPass(allowance: 0.02)) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[1], fraction: 0.25)])
    }
    #expect(tp3.metadata["warning"]?.contains("1 \(ignoredAnchors)") == true)
}

@Test func ops2DProfileOverlappingManualAnchorsAreReportedOnce() throws {
    // Two anchors a hair apart on a 20 in loop merge into one tab; the operator asked for two.
    let (tp, ctx) = try tabbedProfile([F.rect(0, 0, 6, 4)], lastPass: ProfileLastPass(allowance: 0.02)) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1,
                    manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15), TabAnchor(shapeID: ids[0], fraction: 0.16)])
    }
    #expect(tabCount(tp, ctx) == 2)   // one tab, cut by the roughing and the last pass
    let w = try #require(tp.metadata["warning"])
    #expect(w.contains("1 \(fewerTabs)") && w.contains("fewest placed: 1"))
}

@Test func ops2DProfileLaysOutTabsOnTheLastPassWhereRoughingHadNoLoop() throws {
    // A 0.4 in wide slot cut inside with a 1/4 in tool and a 0.1 in last-pass allowance: the
    // roughing offset (0.225 a side) swallows the slot and only the last pass cuts it. It lays
    // out its own two tabs, with nothing else selected, with an open vector selected too (open
    // chains are no roughing loops), and beside a wider part whose roughing loop survived.
    let slot = F.rect(0, 0, 0.4, 2), line = Path(points: [Vec2(0, 3), Vec2(4, 3)], closed: false), wide = F.rect(3, 0, 2, 2)
    let last = ProfileLastPass(allowance: 0.1)
    let (alone, ctx) = try tabbedProfile([slot], side: .inside, lastPass: last) { _ in quarterTabs }
    #expect(tabCount(alone, ctx) == 2 && alone.metadata["warning"] == nil)
    let (withLine, ctx2) = try tabbedProfile([slot, line], select: [1], side: .inside, lastPass: last) { _ in quarterTabs }
    #expect(tabCount(withLine, ctx2) == 2 && noTabWarning(withLine))   // the open vector has its own "cut on the line" note
    let (beside, ctx3) = try tabbedProfile([slot, wide], select: [1], side: .inside, lastPass: last) { _ in quarterTabs }
    #expect(tabCount(beside, ctx3) == 6 && beside.metadata["warning"] == nil)   // wide: 2 twice; slot: 2 once
    // Manual anchors resolve on the pass that cuts the loop: one on the slot is placed and not
    // reported; one on a deleted vector is reported once.
    let (anchored, ctx4) = try tabbedProfile([slot, line], select: [1], side: .inside, lastPass: last) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.3)])
    }
    #expect(tabCount(anchored, ctx4) == 1 && noTabWarning(anchored))
    let (gone, _) = try tabbedProfile([slot, line], select: [1], side: .inside, lastPass: last) { _ in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: UUID(), fraction: 0.5)])
    }
    #expect(gone.metadata["warning"]?.contains("1 \(ignoredAnchors): not on a closed vector this toolpath cuts, or the vector is gone; no tab placed for them") == true)
}

@Test func tabAnchorsOffTheToolpathsClosedShapesOrBeyondReachAreReturnedNotAttached() throws {
    var doc = Document()
    let near = Shape(layerID: doc.defaultLayerID, paths: [F.rect(0, 0, 4, 2)])
    let far = Shape(layerID: doc.defaultLayerID, paths: [F.rect(10, 0, 4, 2)])
    let line = Shape(layerID: doc.defaultLayerID, paths: [Path(points: [Vec2(0, 2.1), Vec2(4, 2.1)], closed: false)])
    doc.add(near); doc.add(far); doc.add(line)
    let loop = try #require(TabAnchors.chain(near.paths[0], tolerance: 0.001))
    let gone = TabAnchor(shapeID: UUID(), fraction: 0.25)
    let anchors = [TabAnchor(shapeID: near.id, fraction: 0.25), TabAnchor(shapeID: far.id, fraction: 0.25),
                   TabAnchor(shapeID: line.id, fraction: 0.5), gone]
    let all: Set<UUID> = [near.id, far.id, line.id]
    let r = TabAnchors.centers(for: anchors, loops: [loop], shapeIDs: [near.id], maxDistance: 0.5, document: doc, tolerance: 0.001)
    #expect(r.centers == [[3]] && r.ignored == Array(anchors[1...]))
    // Selected but beyond reach (its own loop is gone) or on an open path: still not attached.
    #expect(TabAnchors.centers(for: anchors, loops: [loop], shapeIDs: all, maxDistance: 0.5, document: doc, tolerance: 0.001).ignored == Array(anchors[1...]))
    // Within reach and selected: the far shape's anchor lands on the only loop.
    #expect(TabAnchors.centers(for: anchors, loops: [loop], shapeIDs: all, maxDistance: 100, document: doc, tolerance: 0.001).ignored == [anchors[2], gone])
}
