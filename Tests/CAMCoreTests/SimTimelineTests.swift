import CADCore
import Foundation
import Testing
@testable import CAMCore

private let job = JobSetup(width: 10, height: 10, thickness: 0.75)
private let coords = MachineCoordinates(job: job)

private func endMill(_ number: Int, id: UUID = UUID()) -> Tool {
    Tool(id: id, name: "EM\(number)", kind: .endMill, number: number, diameter: 0.25,
         stepdown: 0.1, stepover: 0.1, feedRate: 60, plungeRate: 20)
}

/// Rapid to (1,1) safe, plunge 0.2 below safe Z... then a 6" cut at 60 ipm (= 6 s).
private func slot(tool: Tool) -> Toolpath {
    Toolpath(name: "slot", kind: .profile, tool: tool, moves: [
        .rapid(to: coords.machineAtSafeZ(Vec2(1, 1))),
        .linear(to: coords.machine(Vec2(1, 1), depth: 0.1), feed: 18), // 0.3" at 18 ipm = 1 s
        .linear(to: coords.machine(Vec2(7, 1), depth: 0.1), feed: 60), // 6" at 60 ipm = 6 s
        .dwell(seconds: 0.5),
        .rapid(to: coords.machineAtSafeZ(Vec2(7, 1))),                 // 0.3" at 180 ipm = 0.1 s
    ])
}

@Test func simTimeEstimateSumsFeedsRapidsAndDwell() {
    let t = MachiningTimeEstimator.estimate([slot(tool: endMill(1))], rapidRate: 180, toolChangeSeconds: 0)
    #expect(abs(t - (1 + 6 + 0.5 + 0.1)) < 1e-9)
}

@Test func simTimeEstimateAddsToolChangesAndLinkingRapids() {
    let a = endMill(1), b = endMill(2)
    let t = MachiningTimeEstimator.estimate([slot(tool: a), slot(tool: a), slot(tool: b)],
                                            rapidRate: 180, toolChangeSeconds: 30)
    let perPath = 7.6
    let link = 6.0 / 180 * 60 // (7,1) back to (1,1) at safe Z = 2 s
    #expect(abs(t - (3 * perPath + 2 * link + 30)) < 1e-9)
}

@Test func simTimeEstimateCountsAPauseAsAStop() {
    let a = endMill(1), b = endMill(2)
    var paused = slot(tool: a)
    paused.pauseAfter = PauseStep(message: "Flip")
    let perPath = 7.6, link = 6.0 / 180 * 60
    // Same tool on both sides of the pause: one stop.
    let same = MachiningTimeEstimator.estimate([paused, slot(tool: a)], rapidRate: 180, toolChangeSeconds: 30)
    #expect(abs(same - (2 * perPath + link + 30)) < 1e-9)
    // A pause that ends in a tool change is one stop, not two.
    let change = MachiningTimeEstimator.estimate([paused, slot(tool: b)], rapidRate: 180, toolChangeSeconds: 30)
    #expect(abs(change - (2 * perPath + link + 30)) < 1e-9)
    // A pause on the last toolpath is never written, so it adds nothing.
    let last = MachiningTimeEstimator.estimate([slot(tool: a), paused], rapidRate: 180, toolChangeSeconds: 30)
    #expect(abs(last - (2 * perPath + link)) < 1e-9)
}

@Test func simTimeEstimateArcUsesArcLength() {
    let start = coords.machine(Vec2(3, 2), depth: 0.1)
    let tp = Toolpath(name: "c", kind: .profile, tool: endMill(1), moves: [
        .rapid(to: start),
        .arcCW(to: start, center: coords.machineXY(Vec2(2, 2)), feed: 60),
    ])
    let t = MachiningTimeEstimator.estimate([tp], rapidRate: 200, toolChangeSeconds: 0)
    #expect(abs(t - 2 * Double.pi) < 1e-3)
    #expect(MachiningTimeEstimator.estimate([], rapidRate: 200) == 0)
}

@Test func simFormatTime() {
    #expect(MachiningTimeEstimator.format(12) == "12s")
    #expect(MachiningTimeEstimator.format(243) == "4m 03s")
    #expect(MachiningTimeEstimator.format(3912) == "1h 05m 12s")
    // A dwell or tool-change allowance typed as 1e300 used to trap `Int(_:)` (issue #56): a placeholder instead.
    #expect(MachiningTimeEstimator.format(1e300) == "over 1,000,000 h")
    #expect(MachiningTimeEstimator.format(.infinity) == "over 1,000,000 h")
    #expect(MachiningTimeEstimator.format(.nan) == "—")
    #expect(MachiningTimeEstimator.format(-1e300) == "—")
    #expect(MachiningTimeEstimator.format(3_600_000_001) == "over 1,000,000 h")
}

@Test func simTimelinePositionAndToolPosition() {
    let tl = SimulationTimeline(toolpaths: [slot(tool: endMill(1))], rapidRate: 180)
    #expect(abs(tl.totalTime - 7.6) < 1e-9)
    let mid = tl.toolPosition(at: 4)! // 1 s plunge + 3 s of the 6 s cut → x = 4
    #expect(abs(mid.point.x - 4) < 1e-9)
    #expect(abs(mid.point.z - coords.z(depth: 0.1)) < 1e-9)
    #expect(tl.position(at: 100).step == tl.steps.count)
    #expect(tl.position(at: -1).step == 0)
}

@Test func simPlayerSeekForwardAndBackMatchesFullRun() {
    let paths = [slot(tool: endMill(1))]
    var full = MaterialSimulator(job: job, cellSize: 0.05)
    full.apply(paths[0])
    var player = SimulationPlayer(job: job, toolpaths: paths, rapidRate: 180, cellSize: 0.05)
    player.seek(to: 4)
    #expect(player.heightfield.depth(at: Vec2(3, 1)) > 0)
    #expect(player.heightfield.depth(at: Vec2(6, 1)) == 0)
    player.seek(to: 2) // backwards: x reaches 2
    #expect(player.heightfield.depth(at: Vec2(3, 1)) == 0)
    #expect(player.heightfield.depth(at: Vec2(1.5, 1)) > 0)
    player.runToEnd()
    #expect(player.isAtEnd)
    #expect(player.heightfield == full.heightfield)
}

@Test func simMeshHasSurfaceWallsAndBottom() {
    var hf = Heightfield(width: 1, height: 1, cellSize: 0.1)
    hf[5, 5] = 0.25
    let mesh = HeightfieldMesh(heightfield: hf, thickness: 0.5)
    #expect(mesh.positions.count == mesh.normals.count)
    #expect(mesh.positions.count == mesh.colors.count)
    #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertexCount })
    let zs = stride(from: 2, to: mesh.positions.count, by: 3).map { mesh.positions[$0] }
    #expect(zs.min() == -0.5)
    #expect(zs.contains(-0.25))
    let xs = stride(from: 0, to: mesh.positions.count, by: 3).map { mesh.positions[$0] }
    #expect(xs.min() == 0)
    #expect(abs(xs.max()! - 1) < 1e-6)
    // Decimation keeps the vertex budget.
    let big = Heightfield(width: 100, height: 100, cellSize: 0.05)
    #expect(HeightfieldMesh(heightfield: big, thickness: 1, maxVertices: 10_000).vertexCount < 12_000)
}

@Test func simOverlaySeparatesRapidsCutsAndPlunges() {
    let overlay = ToolpathOverlay(toolpaths: [slot(tool: endMill(1))], coords: coords)
    #expect(overlay.plunges.count == 1)
    #expect(overlay.plunges[0].point == Vec2(1, 1))
    let cuts = overlay.strokes.filter { !$0.isRapid }
    #expect(cuts.count == 1)
    #expect(abs(cuts[0].depth - 0.1) < 1e-9)
    #expect(cuts[0].points == [Vec2(1, 1), Vec2(7, 1)])
    #expect(abs(overlay.maxDepth - 0.1) < 1e-9)
}

@Test func simToolShapeFromTool() {
    var v = endMill(1); v.kind = .vBit; v.angle = 60; v.diameter = 0.5
    guard case .vee(let r, _, let half) = ToolShape(tool: v) else { Issue.record("not vee"); return }
    #expect(r == 0.25)
    #expect(abs(half - Double.pi / 6) < 1e-12)
    #expect(ToolShape(tool: endMill(1)) == .flat(radius: 0.125))
    var d = endMill(1); d.kind = .drill
    #expect(ToolShape(tool: d) == .flat(radius: 0.125))
}
