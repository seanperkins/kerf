import CADCore
import Foundation
import Testing
@testable import CAMCore

private func shaped(_ kind: ToolKind, _ d: Double, _ shape: CutterShape) -> Tool {
    Tool(name: "s", kind: kind, diameter: d, stepdown: 0.1, stepover: 0.05, feedRate: 60, plungeRate: 20, shape: shape)
}

@Test func simBullNosePlungeHasFlatBottomAndRoundedCorner() {
    let job = JobSetup(width: 2, height: 2, thickness: 0.75)
    var sim = MaterialSimulator(job: job, cellSize: 0.005)
    let bull = shaped(.endMill, 0.5, .bullNose(cornerRadius: 0.1))
    #expect(ToolShape(tool: bull) == .shaped(radius: 0.25, shape: .bullNose(cornerRadius: 0.1)))
    let c = MachineCoordinates(job: job)
    sim.apply(Toolpath(name: "p", kind: .drill, tool: bull, moves: [
        .rapid(to: c.machineAtSafeZ(Vec2(1, 1))), .linear(to: c.machine(Vec2(1, 1), depth: 0.3), feed: 20),
        .rapid(to: c.machineAtSafeZ(Vec2(1, 1))),
    ]))
    let hf = sim.heightfield
    #expect(abs(Double(hf.depth(at: Vec2(1.1025, 1.0025))) - 0.3) < 1e-5) // on the flat (r < 0.15)
    let p = Vec2(1.2225, 1.0025)
    let rr = (p - Vec2(1, 1)).length
    let u = rr - 0.15
    let expected = 0.3 - (0.1 - (0.01 - u * u).squareRoot())
    #expect(abs(Double(hf.depth(at: p)) - expected) < 1e-4)
}

@Test func dropCutterUsesTaperedBallOutline() {
    let tool = shaped(.ballNose, 0.25, .taperedBallNose(tipRadius: 0.03125, halfAngle: 10))
    let prof = CutterProfile(tool: tool)
    for r in stride(from: 0.0, through: 0.125, by: 0.01) {
        #expect(abs(prof.height(at: r) - tool.heightAboveTip(atRadius: r)!) < 1e-12)
    }
    #expect(CutterProfile(tool: ToolLibrary.seeded.tools[3]).shape == .ball) // plain ball nose unchanged
}

@Test func mouldingWithFormToolNeverCutsBelowTheSection() throws {
    // Section: flat 0.5 wide then a 0.25 step down. A roundover-like form tool.
    let section = MouldingOperation.SectionProfile(width: 1, samples: [(0, 0), (0.5, 0), (0.5001, 0.25), (1, 0.25)])
    let pts = [FormToolPoint(height: 0, radius: 0.05), FormToolPoint(height: 0.1, radius: 0.15),
               FormToolPoint(height: 0.4, radius: 0.25)]
    let tool = shaped(.endMill, 0.5, .form(points: pts))
    let depths = MouldingOperation.tipDepths(section, tool: tool, step: 0.02, extra: 0)
    for (t, d) in depths {
        for k in -50...50 {
            let u = tool.radius * Double(k) / 50
            let h = tool.heightAboveTip(atRadius: abs(u))!
            #expect(d - h <= section.depth(at: t + u) + 1e-3, "t \(t) u \(u)")
        }
    }
    #expect(EngraveOperation.cutWidth(tool: tool, depth: 0.1) > 0.29)
}
