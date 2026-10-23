import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func holeMill(_ params: HoleMillParameters, paths: [Path] = [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5)],
                      zZero: ZZeroMode = .materialTop) throws -> (Toolpath, CAMContext) {
    let (ctx, ids) = F.document(paths, zZero: zZero)
    let tps = try HoleMillOperation(setup: OperationSetup(name: "H", toolID: F.endMill.id, shapeIDs: ids), params: params)
        .generate(in: ctx)
    #expect(tps.count == 1)
    return (tps[0], ctx)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DHoleMillHelicalBoreStaysOnTheHoleRadius(mode: ZZeroMode) throws {
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.3), zZero: mode)
    #expect(tp.kind == .holeMill)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.3)) < 1e-9)
    let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    // The tool centre runs at hole radius − tool radius (0.375), or returns to the centre.
    for q in cut {
        let r = q.xy.distance(to: Vec2(3, 3))
        #expect(abs(r - 0.375) < 0.001 || r < 1e-9)
    }
    // Depth never increases by more than the stepdown (0.125) per turn: monotone descent.
    var prev = 0.0
    for q in cut {
        let d = ctx.coords.depth(ofMachineZ: q.z)
        #expect(d >= prev - 1e-9)
        prev = d
    }
    // Helix is counter-clockwise for climb.
    let ring = cut.filter { abs($0.xy.distance(to: Vec2(3, 3)) - 0.375) < 0.001 }.prefix(40).map(\.xy)
    let a0 = (ring[0] - Vec2(3, 3)).angle, a1 = (ring[5] - Vec2(3, 3)).angle
    #expect(sin(a1 - a0) > 0)
}

@Test func ops2DHoleMillSkipsHolesSmallerThanTheTool() throws {
    let paths = [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5), ShapeFactory.circle(center: Vec2(6, 3), radius: 0.1)]
    let (tp, _) = try holeMill(HoleMillParameters(cutDepth: 0.2), paths: paths)
    #expect(tp.metadata["holes"] == "1")
    #expect(tp.metadata["warning"]?.contains("1 hole") == true)
    #expect(throws: CAMError.self) {
        try holeMill(HoleMillParameters(cutDepth: 0.2), paths: [ShapeFactory.circle(center: Vec2(1, 1), radius: 0.05)])
    }
}

@Test func ops2DHoleMillThreadClimbsUpOneTurnPerPitch() throws {
    var p = HoleMillParameters(mode: .thread, cutDepth: 0.5, threadPitch: 0.1)
    p.holeDiameter = 0.75
    let (tp, ctx) = try holeMill(p)
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > -0.2 && $0.z < ctx.coords.safeZ - 1e-9 }
    let ring = cut.filter { abs($0.xy.distance(to: Vec2(3, 3)) - 0.25) < 0.001 }
    #expect(!ring.isEmpty)
    // Goes up from the cut depth: 5 turns of 0.1.
    let depths = ring.map { ctx.coords.depth(ofMachineZ: $0.z) }
    #expect(abs(depths.first! - 0.5) < 1e-9)
    #expect(abs(depths.last! - 0.0) < 1e-9)
    #expect(zip(depths, depths.dropFirst()).allSatisfy { $0.1 <= $0.0 + 1e-12 })
    // Total angle swept = 5 turns.
    var sweep = 0.0
    for (a, b) in zip(ring, ring.dropFirst()) {
        var d = (b.xy - Vec2(3, 3)).angle - (a.xy - Vec2(3, 3)).angle
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        sweep += d
    }
    #expect(abs(sweep - 10 * .pi) < 0.01)
    // Never deeper than the cut depth.
    #expect(abs(tp.minZ! + 0.5) < 1e-9)
}

@Test func ops2DHoleMillConventionalThreadEndsAtTheCutDepth() throws {
    var p = HoleMillParameters(mode: .thread, cutDepth: 0.45, threadPitch: 0.1, direction: .conventional)
    p.holeDiameter = 0.75
    let (tp, _) = try holeMill(p)
    #expect(abs(tp.minZ! + 0.45) < 1e-9)
}

@Test func ops2DHoleMillNeverFeedsThroughTheUncutCore() throws {
    // 1" hole, 1/4" tool: the ring leaves a 0.5" core standing in the middle.
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.5))
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    let atDepth = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    #expect(!atDepth.isEmpty)
    for q in atDepth { #expect(q.xy.distance(to: Vec2(3, 3)) > 0.375 - 0.001) }

    // 1/2" hole, 1/4" tool: no core, so the tool may move to the centre before lifting.
    var small = HoleMillParameters(cutDepth: 0.3)
    small.holeDiameter = 0.5
    let (tp2, ctx2) = try holeMill(small)
    let centre = F.densePoints(tp2.moves).filter {
        ctx2.coords.depth(ofMachineZ: $0.z) > 1e-9 && $0.xy.distance(to: Vec2(3, 3)) < 1e-9
    }
    #expect(!centre.isEmpty)
}

// MARK: Helix angle and the peck fallback (issue #12)

/// The steepest descent, in degrees from horizontal, over the segments of `tp` that move sideways while going down.
private func steepestHelixAngle(_ tp: Toolpath, _ ctx: CAMContext) -> Double {
    let pts = F.densePoints(tp.moves)
    var worst = 0.0
    for (a, b) in zip(pts, pts.dropFirst()) {
        let dz = a.z - b.z                       // down is positive
        let across = a.xy.distance(to: b.xy)
        guard dz > 1e-9, across > 1e-9 else { continue }
        worst = max(worst, atan2(dz, across) * 180 / .pi)
    }
    return worst
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DHoleMillHelixNeverDescendsSteeperThanTheRampAngle(mode: ZZeroMode) throws {
    // 1/4 in tool in holes 0.06 to 0.5 in larger, 0.5 deep at the tool's 0.125 pitch: the small ones would ask for a
    // far steeper helix than the ramp angle allows and turn more often instead.
    for extra in [0.06, 0.08, 0.12, 0.25, 0.5] {
        let r = (0.25 + extra) / 2
        let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.5), paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: r)], zZero: mode)
        #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty, "extra \(extra)")
        #expect(steepestHelixAngle(tp, ctx) <= HoleMillOperation.maxHelixAngle + 1e-6, "extra \(extra): \(steepestHelixAngle(tp, ctx))°")
        #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.5)) < 1e-9)
        // Held to the angle where the asked-for pitch is steeper: those say so; the roomy ones do not.
        let clamped = tp.metadata["warning"]?.contains("ramp") == true
        #expect(clamped == (extra < 0.2), "extra \(extra): \(tp.metadata["warning"] ?? "nil")")
    }
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DHoleMillPeckDrillsAHoleTooCloseToTheToolForAHelix(mode: ZZeroMode) throws {
    // 0.01 in larger than the tool and the size of the tool itself: no helix, pecks at the centre with retracts.
    for extra in [0.01, 0.0] {
        let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.5), paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: (0.25 + extra) / 2)], zZero: mode)
        #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty, "extra \(extra)")
        #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.5)) < 1e-9)
        #expect(tp.metadata["warning"]?.contains("peck-drilled instead") == true, "extra \(extra)")
        // The cutting stays within the tool-centre radius of the hole (extra / 2), and where there is any room a lap at that
        // radius at the bottom of each peck makes the hole its full size; none for a hole the size of the tool.
        let cut = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
        let reach = cut.map { $0.xy.distance(to: Vec2(3, 3)) }.max() ?? 0
        #expect(abs(reach - extra / 2) < 1e-3, "extra \(extra): reaches \(reach)")
        let bottomLap = cut.filter { abs(ctx.coords.depth(ofMachineZ: $0.z) - 0.5) < 1e-9 && $0.xy.distance(to: Vec2(3, 3)) > extra / 4 }
        #expect(bottomLap.isEmpty == (extra == 0), "extra \(extra)")
        // 0.5 in at the 0.125 in pitch: four pecks, so three retracts to safe Z between them.
        let retracts = zip(tp.moves, tp.moves.dropFirst()).filter { a, b in
            if case .linear = a, case .rapid(let to) = b { return abs(to.z - ctx.coords.safeZ) < 1e-9 }
            return false
        }.count
        #expect(retracts >= 3, "extra \(extra): \(retracts)")
    }
}

@Test func ops2DHoleMillRoomyHolesAreUnchanged() throws {
    // The 1 in hole of the first test: a 3° helix at the tool's pitch, no warning.
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.3))
    #expect(tp.metadata["warning"] == nil)
    #expect(steepestHelixAngle(tp, ctx) < 4)
}

@Test func ops2DHoleMillThreadSaysWhenAHoleLeavesNoRoomForIt() throws {
    var p = HoleMillParameters(mode: .thread, cutDepth: 0.5, threadPitch: 0.1)
    p.holeDiameter = 0.25            // as large as the 1/4 in tool
    let (tp, _) = try holeMill(p, paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5), ShapeFactory.circle(center: Vec2(6, 3), radius: 0.5)])
    #expect(tp.metadata["warning"]?.contains("2 hole(s) are as large as the tool: no room to mill a thread") == true)
}

@Test func ops2DHoleMillAFinePitchTheUserChoseStaysAHelixHoweverManyTurnsItTakes() throws {
    // 0.5 in deep at a 0.005 in pitch is 100 turns, and a 1 in hole's 3 degree helix is well inside the ramp angle: it is the
    // pitch asked for, not the limit, so it is not turned into a peck drill.
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.5, helixPitch: 0.005))
    #expect(tp.metadata["warning"] == nil)
    let ring = F.densePoints(tp.moves).filter { ctx.coords.depth(ofMachineZ: $0.z) > 1e-9 }
    #expect(ring.contains { abs($0.xy.distance(to: Vec2(3, 3)) - 0.375) < 1e-3 })
    #expect(steepestHelixAngle(tp, ctx) < 1)
}

@Test func ops2DHoleMillPeckFallbackWorksBelowAStartDepth() throws {
    // A start depth is where the material begins: the pecks and their laps run from it down, each peck feeding down from the top
    // of what is cleared.
    var p = HoleMillParameters(cutDepth: 0.5)
    p.startDepth = 0.2
    let (tp, ctx) = try holeMill(p, paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.13)])
    #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
    #expect(abs(tp.minZ! - ctx.coords.z(depth: 0.5)) < 1e-9)
    var feedDepths: [Double] = []
    for m in tp.moves {
        if case .linear(let to, _) = m { feedDepths.append(ctx.coords.depth(ofMachineZ: to.z)) }
    }
    let pecks: [Double] = [0.325, 0.45, 0.5]   // the 0.125 pitch from the 0.2 start depth: 0.325, 0.45, then the cut depth
    for peck in pecks {
        #expect(feedDepths.contains { abs($0 - peck) < 1e-6 }, "feeds down to \(peck)")
    }
    // The first way down into the material is fed, through what stands above the start depth too; later pecks rapid down the
    // column the previous one cut.
    var fedBelowTheTop = false, rapidedFirst = false
    for m in tp.moves {
        switch m {
        case .rapid(let to) where ctx.coords.depth(ofMachineZ: to.z) > 1e-9: if !fedBelowTheTop { rapidedFirst = true }
        case .linear(let to, _) where ctx.coords.depth(ofMachineZ: to.z) > 1e-9: fedBelowTheTop = true
        default: break
        }
    }
    #expect(fedBelowTheTop && !rapidedFirst)
    #expect(tp.metadata["warning"]?.contains("peck-drilled instead") == true)
}

@Test func ops2DHoleMillBoundsTheWorkOfAHugeDepthOrATinyPitch() throws {
    // A deep cut at a fine pitch that would take more than 10 000 turns is refused (fewer turns would make the helix steeper than
    // the ramp angle); one that fits is cut at its pitch, with the angle held. An infinite depth is refused.
    #expect(throws: CAMError.self) { try holeMill(HoleMillParameters(cutDepth: 1e6, helixPitch: 1e-6)) }
    // (A pitch below the tolerance, 0.001 in here, is taken as the tolerance.)
    #expect(throws: CAMError.self) { try holeMill(HoleMillParameters(cutDepth: 20, helixPitch: 1e-4)) }        // 20 000 turns
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 5, helixPitch: 1e-4))                            // 5 000 turns
    #expect(steepestHelixAngle(tp, ctx) < 1)
    #expect(tp.moves.count < 2_000_000)
    #expect(throws: CAMError.self) { try holeMill(HoleMillParameters(cutDepth: .infinity)) }
    #expect(throws: CAMError.self) { try holeMill(HoleMillParameters(startDepth: -.infinity, cutDepth: 0.5)) }
}

@Test func ops2DHoleMillRefusesAHelixPitchThatIsNotAPositiveNumber() throws {
    for pitch in [Double.nan, .infinity, 0, -0.1] {
        #expect(throws: CAMError.self, "pitch \(pitch)") { try holeMill(HoleMillParameters(cutDepth: 0.5, helixPitch: pitch)) }
    }
    // A flat lap at the bottom of a peck: it moves sideways at the peck's own depth, never down on a slant.
    let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: 0.5), paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.13)])
    let pts = F.densePoints(tp.moves)
    for (a, b) in zip(pts, pts.dropFirst()) where a.xy.distance(to: b.xy) > 1e-9 {
        #expect(abs(a.z - b.z) < 1e-9 || a.z >= ctx.coords.safeZ - 1e-9 || b.z >= ctx.coords.safeZ - 1e-9, "a sideways move that also changes depth")
    }
}

@Test func ops2DHoleMillTheCutMovesThemselvesStayWithinTheRampAngle() throws {
    // The limit is on the straight moves the helix is cut in, whose chords are shorter than the arc: the case that measured
    // 10.05 degrees when the limit was worked out on the circumference (0.03 in radius, 0.3323685283 in deep).
    for depth in [0.3323685283, 0.2, 0.45, 0.5, 0.7, 1.1] {
        for extra in [0.06, 0.07, 0.1, 0.15] {
            let (tp, ctx) = try holeMill(HoleMillParameters(cutDepth: depth), paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: (0.25 + extra) / 2)])
            #expect(steepestHelixAngle(tp, ctx) <= HoleMillOperation.maxHelixAngle + 1e-6, "depth \(depth) extra \(extra): \(steepestHelixAngle(tp, ctx))")
        }
    }
    // A cut that would take more pecks than the bound is refused, not given deeper pecks.
    #expect(throws: CAMError.self) {
        try holeMill(HoleMillParameters(cutDepth: 1e6, helixPitch: 0.05), paths: [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.13)])
    }
}

@Test func ops2DHoleMillRefusesDiametersThatAreNotPositiveNumbers() throws {
    for d in [Double.nan, .infinity, 0, -0.5] {
        #expect(throws: CAMError.self, "hole diameter \(d)") { try holeMill(HoleMillParameters(cutDepth: 0.5, holeDiameter: d)) }
    }
}
