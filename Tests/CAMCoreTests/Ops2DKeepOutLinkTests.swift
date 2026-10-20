import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func square(_ x: Double, _ y: Double, _ s: Double) -> [Vec2] {
    [Vec2(x, y), Vec2(x + s, y), Vec2(x + s, y + s), Vec2(x, y + s)]
}

private func profile(_ ids: [UUID], depth: Double, name: String, tool: Tool = F.endMill) -> AnyOperation {
    var params = ProfileParameters(depth: DepthSettings(cutDepth: depth))
    params.tabs.isEnabled = false
    return .profile(ProfileOperation(setup: OperationSetup(name: name, toolID: tool.id, shapeIDs: ids), params: params))
}

/// Two profiles in separate operations on either side of a zone taller than safe Z: each
/// operation is re-routed alone, so only the travel between them crosses the zone.
@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DKeepOutTravelBetweenToolpathsIsCheckedAndLifted(mode: ZZeroMode) throws {
    var (ctx, ids) = F.document([F.rect(1, 1, 1, 1), F.rect(6, 1, 1, 1)], zZero: mode)
    let zone = KeepOutZone(name: "TallClamp", outline: [Vec2(3.5, 0.5), Vec2(5, 0.5), Vec2(5, 2.5), Vec2(3.5, 2.5)],
                           height: 1.0, liftOver: true)
    ctx.document.keepOutZones = [zone]
    let a = try profile([ids[0]], depth: 0.25, name: "A").generate(in: ctx)[0]
    let b = try profile([ids[1]], depth: 0.25, name: "B").generate(in: ctx)[0]
    let check = { (tps: [Toolpath]) in
        KeepOut.violations(tps, zones: [zone], coords: ctx.coords, margin: 0.05, tolerance: 0.0005)
    }
    // Each toolpath alone is fine; the program as a whole is not.
    #expect(check([a]).isEmpty && check([b]).isEmpty)
    let raw = check([a, b])
    #expect(raw.contains { $0.toolpathName == "B" && $0.isRapid })

    let linked = KeepOutAvoidance.link([a, b], zones: [zone], coords: ctx.coords, margin: 0.05, tolerance: 0.0005)
    #expect(check(linked).isEmpty)
    #expect(linked[0].moves == a.moves)
    #expect(linked[1].moves.count > b.moves.count)
    let lead = linked[1].moves.prefix(3).allSatisfy { $0.isRapid }
    #expect(lead)
    #expect(linked[1].moves.compactMap(\.target).map(\.z).max()! >= ctx.coords.z(aboveTop: 1.05) - 1e-9)

    // After a tool change the position is unknown: not flagged, not changed.
    let c = try profile([ids[1]], depth: 0.25, name: "C", tool: F.smallEndMill).generate(in: ctx)[0]
    #expect(check([a, c]).isEmpty)
    #expect(KeepOutAvoidance.link([a, c], zones: [zone], coords: ctx.coords, margin: 0.05,
                                  tolerance: 0.0005)[1].moves == c.moves)

    // A check-only zone is reported for the same travel and never re-routed.
    var plain = zone
    plain.liftOver = nil
    #expect(!KeepOut.violations([a, b], zones: [plain], coords: ctx.coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(KeepOutAvoidance.link([a, b], zones: [plain], coords: ctx.coords, margin: 0.05,
                                  tolerance: 0.0005)[1].moves == b.moves)
}

/// A profile corner inside a lift-over zone: the cut leaving the zone must re-plunge at its
/// real start and stay at pass depth, not ramp down from the clearance height.
@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func ops2DKeepOutLiftResumesAtTrueStart(mode: ZZeroMode) throws {
    var (ctx, ids) = F.document([F.rect(1, 1, 2, 2)], zZero: mode)
    let zone = KeepOutZone(name: "Z", outline: square(2.6, 2.6, 1), height: 0.5, liftOver: true)
    ctx.document.keepOutZones = [zone]
    let tp = try profile(ids, depth: 0.5, name: "P").generate(in: ctx)[0]
    let coords = ctx.coords
    #expect(KeepOut.violations([tp], zones: [zone], coords: coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    #expect(F.conventionViolations(tp, coords: coords).isEmpty)
    #expect(Int(tp.metadata["keep-out lifts"] ?? "0")! >= 1)

    // No feed move enters the material from above its top while also moving in XY.
    let topZ = coords.z(aboveTop: 0)
    var cur: Vec3?
    for m in tp.moves {
        guard let t = m.target else { continue }
        defer { cur = t }
        guard let s = cur, !m.isRapid else { continue }
        let ramps = s.z > topZ + 1e-9 && t.z < topZ - 1e-9 && s.xy.distance(to: t.xy) > 1e-6
        #expect(!ramps, "feed move from \(s) to \(t) ramps in from above the material")
    }

    // The right edge (x = 3.125) below the grown zone is cut at full depth everywhere.
    var segs: [(Vec3, Vec3)] = []
    cur = nil
    for m in tp.moves {
        guard let t = m.target else { continue }
        if let s = cur, case .linear = m,
           coords.depth(ofMachineZ: s.z) > 0.5 - 1e-6, coords.depth(ofMachineZ: t.z) > 0.5 - 1e-6 {
            segs.append((s, t))
        }
        cur = t
    }
    for y in stride(from: 1.0, through: 2.3, by: 0.05) {
        let q = coords.machineXY(Vec2(3.125, y))
        let covered = segs.contains { s, t in
            Polygon2D.distance(from: q, toLoop: [s.xy, t.xy]) < 1e-4
        }
        #expect(covered, "right edge not cut to depth at y=\(y)")
    }
}
