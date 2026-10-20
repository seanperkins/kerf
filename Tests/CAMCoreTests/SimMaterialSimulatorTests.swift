import CADCore
import Foundation
import Testing
@testable import CAMCore

private func tool(_ kind: ToolKind, diameter: Double, angle: Double? = nil) -> Tool {
    Tool(name: "t", kind: kind, diameter: diameter, angle: angle, stepdown: 0.1, stepover: 0.1,
         feedRate: 60, plungeRate: 20)
}

private func plunge(at p: Vec2, depth: Double, tool t: Tool, job: JobSetup) -> Toolpath {
    let c = MachineCoordinates(job: job)
    return Toolpath(name: "plunge", kind: .drill, tool: t, moves: [
        .rapid(to: c.machineAtSafeZ(p)),
        .linear(to: c.machine(p, depth: depth), feed: 20),
        .rapid(to: c.machineAtSafeZ(p)),
    ])
}

@Test func simFlatPlungeMakesFlatBottomHole() {
    for mode in [ZZeroMode.materialTop, .spoilboard] {
        let job = JobSetup(width: 4, height: 4, thickness: 0.75, zZero: mode)
        var sim = MaterialSimulator(job: job, cellSize: 0.01)
        sim.apply(plunge(at: Vec2(2, 2), depth: 0.25, tool: tool(.endMill, diameter: 0.5), job: job))
        let hf = sim.heightfield
        // Flat bottom across the radius.
        for r in [0.0, 0.1, 0.2, 0.235] {
            #expect(abs(hf.depth(at: Vec2(2 + r, 2)) - 0.25) < 1e-5, "mode \(mode) r \(r)")
            #expect(abs(hf.depth(at: Vec2(2, 2 - r)) - 0.25) < 1e-5)
        }
        // Untouched just outside the radius.
        #expect(hf.depth(at: Vec2(2.27, 2)) == 0)
        #expect(hf.depth(at: Vec2(2, 1.73)) == 0)
        // Hole area ≈ πr².
        let cut = hf.depths.filter { $0 > 0 }.count
        let area = Double(cut) * 0.01 * 0.01
        #expect(abs(area - Double.pi * 0.0625) < 0.01)
    }
}

@Test func simVBitPlungeMakesCone() {
    let job = JobSetup(width: 2, height: 2, thickness: 0.75)
    var sim = MaterialSimulator(job: job, cellSize: 0.005)
    let vbit = tool(.vBit, diameter: 0.5, angle: 90)
    sim.apply(plunge(at: Vec2(1, 1), depth: 0.2, tool: vbit, job: job))
    let hf = sim.heightfield
    // 90° V: depth = 0.2 - r; surface width at the top = 0.4.
    for r in [0.0, 0.05, 0.1, 0.15] {
        // Sample at a cell centre; rr is its distance from the tool axis.
        let d = Double(hf.depth(at: Vec2(1 + r + 0.0025, 1.0025)))
        let rr = (Vec2(1 + r + 0.0025, 1.0025) - Vec2(1, 1)).length
        #expect(abs(d - (0.2 - rr)) < 0.006, "r \(r): \(d)")
    }
    #expect(hf.depth(at: Vec2(1.21, 1)) == 0)
    #expect(abs(Double(hf.maxDepth) - 0.2) < 0.006)
}

@Test func simBallNoseIsSpherical() {
    let job = JobSetup(width: 2, height: 2, thickness: 0.75)
    var sim = MaterialSimulator(job: job, cellSize: 0.005)
    sim.apply(plunge(at: Vec2(1, 1), depth: 0.25, tool: tool(.ballNose, diameter: 0.5), job: job))
    let hf = sim.heightfield
    for x in [1.0025, 1.1025, 1.2025] {
        let rr = (Vec2(x, 1.0025) - Vec2(1, 1)).length
        let expected = 0.25 - (0.25 - (0.0625 - rr * rr).squareRoot())
        #expect(abs(Double(hf.depth(at: Vec2(x, 1.0025))) - expected) < 1e-4)
    }
}

@Test func simLinearSlotAndThroughCutClamp() {
    let job = JobSetup(width: 6, height: 2, thickness: 0.5)
    let c = MachineCoordinates(job: job)
    let t = tool(.endMill, diameter: 0.25)
    let tp = Toolpath(name: "slot", kind: .profile, tool: t, moves: [
        .rapid(to: c.machineAtSafeZ(Vec2(1, 1))),
        .linear(to: c.machine(Vec2(1, 1), depth: 0.6), feed: 20),
        .linear(to: c.machine(Vec2(5, 1), depth: 0.6), feed: 60),
        .rapid(to: c.machineAtSafeZ(Vec2(5, 1))),
    ])
    var sim = MaterialSimulator(job: job, cellSize: 0.01)
    sim.apply(tp)
    let hf = sim.heightfield
    #expect(hf.depth(at: Vec2(3, 1)) == 0.5) // clamped to thickness
    #expect(hf.depth(at: Vec2(3, 1.1)) == 0.5)
    #expect(hf.depth(at: Vec2(3, 1.14)) == 0)
    #expect(hf.depth(at: Vec2(5.2, 1)) == 0)
}

@Test func simArcCutsAlongCircle() {
    let job = JobSetup(width: 4, height: 4, thickness: 0.75, xyOrigin: .center)
    let c = MachineCoordinates(job: job)
    let t = tool(.endMill, diameter: 0.125)
    let start = c.machine(Vec2(3, 2), depth: 0.1)
    let tp = Toolpath(name: "circle", kind: .profile, tool: t, moves: [
        .rapid(to: c.machineAtSafeZ(Vec2(3, 2))),
        .linear(to: start, feed: 20),
        .arcCCW(to: start, center: c.machineXY(Vec2(2, 2)), feed: 60),
        .rapid(to: c.machineAtSafeZ(Vec2(3, 2))),
    ])
    var sim = MaterialSimulator(job: job, cellSize: 0.01)
    sim.apply(tp)
    let hf = sim.heightfield
    for a in stride(from: 0.0, to: 2 * Double.pi, by: 0.5) {
        let p = Vec2(2 + cos(a), 2 + sin(a))
        #expect(abs(hf.depth(at: p) - 0.1) < 1e-5, "angle \(a)")
    }
    #expect(hf.depth(at: Vec2(2, 2)) == 0)
}

@Test func simRapidsAboveStockLeaveItUntouched() {
    let job = JobSetup(width: 4, height: 4, thickness: 0.75)
    let c = MachineCoordinates(job: job)
    let tp = Toolpath(name: "air", kind: .profile, tool: tool(.endMill, diameter: 0.25), moves: [
        .rapid(to: c.machineAtSafeZ(Vec2(0, 0))),
        .rapid(to: c.machineAtSafeZ(Vec2(4, 4))),
        .linear(to: c.machine(Vec2(4, 0), depth: -0.01), feed: 60),
    ])
    var sim = MaterialSimulator(job: job, cellSize: 0.05)
    sim.apply(tp)
    #expect(sim.heightfield.maxDepth == 0)
}
