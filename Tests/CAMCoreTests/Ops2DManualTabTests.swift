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
private func tabbedProfile(_ paths: [Path], select: [Int] = [], side: ProfileSide = .outside, allowance: Double = 0,
                           sharpCorners: Bool = false, lastPass: ProfileLastPass? = nil, asOneShape: Bool = false,
                           tabs: ([UUID]) -> TabSettings) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = asOneShape ? F.document(shapePaths: paths) : F.document(paths)
    var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5), side: side)
    p.tabs = tabs(ids)
    p.allowance = allowance
    p.sharpCorners = sharpCorners ? true : nil
    p.lastPass = lastPass
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: [ids[0]] + select.map { ids[$0] }), params: p)
    return (try op.generate(in: ctx)[0], ctx)
}

private func tabCount(_ tp: Toolpath, _ ctx: CAMContext) -> Int {
    tabEntries(tp, cut: ctx.coords.z(depth: 0.5), top: ctx.coords.z(depth: 0.4)).count
}

/// How many distinct places along the drawn outline `along` the tabs of `tp` rise at (within
/// `radius` of arc length counts as one, and only tabs within `near` of the outline count): two
/// passes that reuse the same tabs stand one allowance apart across the edge but at the same
/// place along it, so they give as many places as tabs.
private func tabPlaces(_ tp: Toolpath, _ ctx: CAMContext, along: Path, radius: Double = 0.05, near: Double = .infinity) throws -> Int {
    let outline = try #require(TabAnchors.chain(along, tolerance: 0.001))
    var places: [Double] = []
    for e in tabEntries(tp, cut: ctx.coords.z(depth: 0.5), top: ctx.coords.z(depth: 0.4)) {
        let pr = outline.project(ctx.coords.materialXY(fromMachine: e.xy))
        guard pr.distance <= near else { continue }
        let s = pr.s
        if !places.contains(where: { d in let gap = abs(d - s); return min(gap, outline.length - gap) < radius }) { places.append(s) }
    }
    return places.count
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
        ("swallowed vector beside", [F.rect(0, 0, 6, 4), F.rect(6.05, 0, 0.2, 1)], [1], .inside, { [TabAnchor(shapeID: $0[1], fraction: 0.6)] }),
        ("swallowed vector touching", [F.rect(0, 0, 6, 4), F.rect(6.001, 0, 0.2, 1)], [1], .inside, { [TabAnchor(shapeID: $0[1], fraction: 0.6)] }),
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
    // The anchor's loop is found by the offset the toolpath applied, however large: a 0.5 in side
    // allowance, and an anchor beside the acute corner of a 30 degree triangle cut inside, where
    // the loop is trimmed far back from the tip.
    let (wide, ctxW) = try tabbedProfile([F.rect(0, 0, 6, 4)], allowance: 0.5, lastPass: ProfileLastPass(allowance: 0.1)) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15)])
    }
    #expect(tabCount(wide, ctxW) == 2 && wide.metadata["warning"] == nil)
    // A negative allowance beyond the tool radius cuts on the line (the offset is clamped at zero),
    // and the anchor is judged at that offset.
    let (onLine, ctxL) = try tabbedProfile([F.rect(0, 0, 6, 4)], allowance: -0.2) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15)])
    }
    #expect(tabCount(onLine, ctxL) == 1 && onLine.metadata["warning"] == nil)
    let triangle = Path(points: [Vec2(0, 0), Vec2(6, 0), Vec2(0, 6 * tan(Double.pi / 6))], closed: true)
    let (acute, ctxA) = try tabbedProfile([triangle], side: .inside, lastPass: ProfileLastPass(allowance: 0.1)) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.35)])
    }
    #expect(tabCount(acute, ctxA) == 2 && acute.metadata["warning"] == nil)
}

@Test func ops2DProfileTabsAreTheSameWithSharpCorners() throws {
    // A mitered outside loop has only corner vertices, none of them one offset from the vector.
    // Anchors must still find their loop wherever the part sits (the loop's start vertex moves
    // with it), with and without a second part to approach from, and the last pass must reuse
    // the roughing tabs rather than lay out its own a little way along.
    let anchors: ([UUID]) -> TabSettings = { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1,
                    manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15), TabAnchor(shapeID: ids[0], fraction: 0.65)])
    }
    for origin in [Vec2(0, 0), Vec2(2, 2)] {
        let rect = F.rect(origin.x, origin.y, 6, 4)
        let (tp, ctx) = try tabbedProfile([rect], sharpCorners: true, tabs: anchors)
        #expect(tabCount(tp, ctx) == 2 && tp.metadata["warning"] == nil, "\(origin)")
        let (two, ctx2) = try tabbedProfile([rect], sharpCorners: true, lastPass: ProfileLastPass(allowance: 0.1), tabs: anchors)
        #expect(tabCount(two, ctx2) == 4 && two.metadata["warning"] == nil, "\(origin)")
        #expect(try tabPlaces(two, ctx2, along: rect) == 2, "\(origin)")
    }
    let (beside, ctx3) = try tabbedProfile([F.rect(0, 0, 6, 4), F.rect(8, 6, 2, 2)], select: [1], sharpCorners: true,
                                           lastPass: ProfileLastPass(allowance: 0.1)) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.15)])
    }
    #expect(tabCount(beside, ctx3) == 2 && beside.metadata["warning"] == nil)
    #expect(try tabPlaces(beside, ctx3, along: F.rect(0, 0, 6, 4)) == 1)
    for allowance in [0.02, 0.1, 0.25] {
        let (auto, ctx4) = try tabbedProfile([F.rect(0, 0, 6, 4)], sharpCorners: true, lastPass: ProfileLastPass(allowance: allowance)) { _ in
            TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
        }
        #expect(tabCount(auto, ctx4) == 8 && auto.metadata["warning"] == nil, "\(allowance)")
        #expect(try tabPlaces(auto, ctx4, along: F.rect(0, 0, 6, 4), radius: 0.3 * allowance + 0.01) == 4, "\(allowance)")
    }
}

@Test func ops2DProfileReportsRoughingTabsThatDoNotReachTheLastPass() throws {
    // Two parts 0.27 in apart cut outside: the roughing offset merges them into one loop and both
    // automatic tabs land on the big part. The last pass cuts two loops; the small part's gets no
    // tab, and laying out fresh ones there would bridge nothing, since the roughing pass has cut
    // through beside them. It is reported instead.
    let (tp, ctx) = try tabbedProfile([F.rect(0, 0, 4, 2), F.rect(4.27, 0, 1, 2)], select: [1],
                                      lastPass: ProfileLastPass(allowance: 0.02)) { _ in quarterTabs }
    #expect(tabCount(tp, ctx) == 4)   // the big part's two, on both passes
    #expect(tp.metadata["warning"] == "tabs did not carry to the last pass on 1 loop(s); the part may come free")
    // A loop too short for any tab on the roughing pass is reported once, as short, not again as
    // lost: a 0.6 in square cut inside with a 0.1 in allowance, alone and beside a tabbed part
    // (whose roughing tabs are not this loop's).
    for paths in [[F.rect(0, 0, 0.6, 0.6)], [F.rect(0, 0, 0.6, 0.6), F.rect(2, 0, 3, 3)]] {
        let (short, ctx2) = try tabbedProfile(paths, select: paths.count == 2 ? [1] : [], side: .inside,
                                              lastPass: ProfileLastPass(allowance: 0.1)) { _ in quarterTabs }
        #expect(tabCount(short, ctx2) == (paths.count == 2 ? 4 : 0))
        #expect(short.metadata["warning"] == "1 \(fewerTabs) (too short, or anchors too close; fewest placed: 0); the part may come free")
    }
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
    #expect(gone.metadata["warning"]?.contains("1 \(ignoredAnchors): not on a stretch of a closed vector this toolpath cuts, or the vector is gone; no tab placed for them") == true)
    // Overlapping anchors on the swallowed slot are reported even beside a surviving loop.
    let (merged, ctx5) = try tabbedProfile([slot, wide], select: [1], side: .inside, lastPass: last) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1,
                    manualTabs: [TabAnchor(shapeID: ids[0], fraction: 0.3), TabAnchor(shapeID: ids[0], fraction: 0.31)])
    }
    #expect(tabCount(merged, ctx5) == 1)
    #expect(merged.metadata["warning"]?.contains("1 \(fewerTabs)") == true)
}

@Test func tabAnchorsAttachOnlyToTheirOwnVectorsLoop() throws {
    var doc = Document()
    let near = Shape(layerID: doc.defaultLayerID, paths: [F.rect(0, 0, 4, 2)])
    let other = Shape(layerID: doc.defaultLayerID, paths: [F.rect(4.3, 0, 1, 2)])
    let line = Shape(layerID: doc.defaultLayerID, paths: [Path(points: [Vec2(0, 2.1), Vec2(4, 2.1)], closed: false)])
    doc.add(near); doc.add(other); doc.add(line)
    func loops(_ shapes: [Shape], offset: Double, join: GeomKernel.Join = .round) -> [ArcLengthChain] {
        ProfileGeometry.loops(closed: ShapeGeometry.loops(of: shapes, tolerance: 0.001).closed, side: .outside, offset: offset,
                              direction: .climb, tolerance: 0.001, join: join).chains.map { ArcLengthChain($0) }
    }
    // Each shape here is a part of its own.
    func alone(_ a: TabAnchor, _ l: [ArcLengthChain], reach: Double) -> TabAnchors.OwnLoops {
        TabAnchors.OwnLoops(outline: [TabAnchors.chain(for: a, in: doc, tolerance: 0.001)!], part: l, vector: l, reach: reach)
    }
    let gone = TabAnchor(shapeID: UUID(), fraction: 0.25)
    let anchors = [TabAnchor(shapeID: near.id, fraction: 0.25), TabAnchor(shapeID: other.id, fraction: 0.25),
                   TabAnchor(shapeID: line.id, fraction: 0.5), gone]
    let all: Set<UUID> = [near.id, other.id, line.id]
    // Only the near anchor: the other rectangle is 0.3 in away but this loop is not its offset,
    // the line is open, the last vector is gone. Selection alone is not enough; so with miter joins.
    for join in [GeomKernel.Join.round, .miter(limit: ProfileGeometry.sharpMiterLimit)] {
        let loop = loops([near], offset: 0.125, join: join)
        let r = TabAnchors.centers(for: anchors, loops: loop, shapeIDs: all, ownLoops: { alone($0, loops([doc.shape(id: $0.shapeID)!], offset: 0.125, join: join), reach: 0.5) },
                                   document: doc, tolerance: 0.001)
        #expect(r.centers.map(\.count) == [1] && r.ignored == 3)
        #expect(abs(r.centers[0][0] - loop[0].project(Vec2(3, 0)).s) < 1e-6)
    }
    // Loops of another offset are not this toolpath's; a loop two vectors merged into is both
    // vectors' offset, and an anchor on the swallowed stretch between them has no loop to go to.
    let loop = loops([near], offset: 0.125)
    #expect(TabAnchors.centers(for: anchors, loops: loop, shapeIDs: all, ownLoops: { alone($0, loops([doc.shape(id: $0.shapeID)!], offset: 0.25), reach: 1) }, document: doc, tolerance: 0.001).ignored == 4)
    let merged = loops([near, other], offset: 0.2)
    #expect(merged.count == 1)
    let r = TabAnchors.centers(for: anchors + [TabAnchor(shapeID: near.id, fraction: 0.4)], loops: merged, shapeIDs: all,
                               ownLoops: { alone($0, loops([doc.shape(id: $0.shapeID)!], offset: 0.2), reach: 0.8) }, document: doc, tolerance: 0.001)
    #expect(r.centers.map(\.count) == [2] && r.ignored == 3)   // near 0.25, other 0.25; near 0.4 faces the gap
}

@Test func ops2DProfileAnchorsOnAPartDrawnAsSeveralShapesFindTheirLoop() throws {
    // A hole drawn as its own shape (DXF import makes one shape per path) inside a 6x4 part, both
    // selected: its anchor's loop is the one the toolpath cuts for the part, outer and hole offset
    // together, not what the hole would get offset alone on the wrong side. Outside and inside,
    // with and without a last pass. Likewise an anchor on one of two overlapping shapes, where the
    // other shape swallows part of its outline: an anchor on the stretch that is cut is placed.
    let outer = F.rect(0, 0, 6, 4), hole = F.rect(2, 1, 2, 2)
    for side in [ProfileSide.outside, .inside] {
        for lastPass in [nil, ProfileLastPass(allowance: 0.1)] {
            let (tp, ctx) = try tabbedProfile([outer, hole], select: [1], side: side, lastPass: lastPass) { ids in
                TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[1], fraction: 0.3)])
            }
            #expect(tabCount(tp, ctx) == (lastPass == nil ? 1 : 2), "\(side) \(String(describing: lastPass))")
            #expect(tp.metadata["warning"] == nil, "\(side) \(String(describing: lastPass))")
        }
    }
    let a = F.rect(0, 0, 2, 2), b = F.rect(1.9, 0, 2.1, 1)
    let onA = try #require(TabAnchors.chain(a, tolerance: 0.001))
    let fraction = onA.project(Vec2(2, 1.5)).s / onA.length
    let (over, ctx) = try tabbedProfile([a, b], select: [1], lastPass: ProfileLastPass(allowance: 0.1)) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: fraction)])
    }
    #expect(tabCount(over, ctx) == 2 && over.metadata["warning"] == nil)
    // An anchor on a stretch of A that B covers (A's right edge runs through B) is on a vector the
    // toolpath cuts, but not on a stretch it cuts: reported, not moved to A's nearest cut edge.
    for lastPass in [nil, ProfileLastPass(allowance: 0.1)] {
        let (covered, ctxC) = try tabbedProfile([a, F.rect(1, 0, 3, 2)], select: [1], lastPass: lastPass) { ids in
            TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: onA.project(Vec2(2, 1)).s / onA.length)])
        }
        #expect(tabCount(covered, ctxC) == 0 && covered.metadata["warning"]?.contains("1 \(ignoredAnchors)") == true, "\(String(describing: lastPass))")
    }
    // Two parts the roughing offset joins (touching, 0.001 in apart, 0.1 in apart) but the last
    // pass does not: an anchor on A's edge just above B's top sits at the joined loop's inner corner
    // on the roughing pass and on A's own stretch on the last pass; both passes hold it.
    for x0 in [2.0, 2.001, 2.1] {
        let (joined, ctxJ) = try tabbedProfile([a, F.rect(x0, 0, 2, 1)], select: [1], lastPass: ProfileLastPass(allowance: 0.1)) { ids in
            TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], fraction: onA.project(Vec2(2, 1.15)).s / onA.length)])
        }
        #expect(tabCount(joined, ctxJ) == 2 && joined.metadata["warning"] == nil, "\(x0)")
    }
    // A hole smaller than the tool in a part whose outer loop survives: cut outside its loop is
    // gone, and its anchor is reported, not moved to the outer loop; cut inside the hole is an
    // island whose loop grows, and the anchor is placed.
    for lastPass in [nil, ProfileLastPass(allowance: 0.1)] {
        for side in [ProfileSide.outside, .inside] {
            let (tiny, ctxT) = try tabbedProfile([outer, F.rect(2.9, 1.9, 0.2, 0.2)], select: [1], side: side, lastPass: lastPass) { ids in
                TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[1], fraction: 0.25)])
            }
            let placed = side == .inside ? (lastPass == nil ? 1 : 2) : 0
            #expect(tabCount(tiny, ctxT) == placed, "\(side) \(String(describing: lastPass))")
            #expect((tiny.metadata["warning"]?.contains("1 \(ignoredAnchors)") ?? false) == (side == .outside), "\(side) \(String(describing: lastPass))")
        }
    }
    // Within one shape each path is its own vector: an anchor on a second path 0.001 in beyond
    // the first, swallowed by an inside cut, is not lent the first path's loop.
    let (two, ctx2) = try tabbedProfile([outer, F.rect(6.001, 0, 0.2, 1)], side: .inside, asOneShape: true) { ids in
        TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, manualTabs: [TabAnchor(shapeID: ids[0], pathIndex: 1, fraction: 0.6)])
    }
    #expect(tabCount(two, ctx2) == 0 && two.metadata["warning"]?.contains("1 \(ignoredAnchors)") == true)
    // A frame cut inside with a last pass: the hole's loop lies inside the outer's, and each
    // last-pass loop takes its own roughing loop's tabs.
    let (frame, ctx3) = try tabbedProfile([outer, hole], side: .inside, lastPass: ProfileLastPass(allowance: 0.1), asOneShape: true) { _ in quarterTabs }
    #expect(tabCount(frame, ctx3) == 8 && frame.metadata["warning"] == nil)
    // (A tab on a corner arc projects onto the outline a little differently from each loop.)
    #expect(try tabPlaces(frame, ctx3, along: outer, radius: 0.25, near: 0.3) == 2 && tabPlaces(frame, ctx3, along: hole, radius: 0.25, near: 0.3) == 2)
}
