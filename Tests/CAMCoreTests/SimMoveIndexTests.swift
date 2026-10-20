import CADCore
import Foundation
import Testing
@testable import CAMCore

private let job = JobSetup(width: 10, height: 10, thickness: 0.75)
private let coords = MachineCoordinates(job: job)

/// Plunge 1 s, cut 6 s, dwell 0.5 s, retract 0.1 s (at 180 ipm rapids).
private func slot() -> Toolpath {
    let tool = Tool(name: "EM", kind: .endMill, number: 1, diameter: 0.25, stepdown: 0.1, stepover: 0.1,
                    feedRate: 60, plungeRate: 20)
    return Toolpath(name: "slot", kind: .profile, tool: tool, moves: [
        .rapid(to: coords.machineAtSafeZ(Vec2(1, 1))),
        .linear(to: coords.machine(Vec2(1, 1), depth: 0.1), feed: 18),
        .linear(to: coords.machine(Vec2(7, 1), depth: 0.1), feed: 60),
        .dwell(seconds: 0.5),
        .rapid(to: coords.machineAtSafeZ(Vec2(7, 1))),
    ])
}

@Test func simMoveIndexStepsByMove() {
    let idx = SimulationMoveIndex(timeline: SimulationTimeline(toolpaths: [slot()], rapidRate: 180))
    #expect(idx.spans.count == 3)
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
    #expect(near(idx.nextBoundary(after: 0), 1))
    #expect(near(idx.nextBoundary(after: 1), 7))
    #expect(near(idx.nextBoundary(after: 3), 7))
    #expect(near(idx.nextBoundary(after: 7), 7.6))   // through the dwell to the retract's end
    #expect(near(idx.nextBoundary(after: 7.6), 7.6)) // end of job
    #expect(near(idx.previousBoundary(before: 7.6), 7.5))
    #expect(near(idx.previousBoundary(before: 7.5), 1))
    #expect(near(idx.previousBoundary(before: 3), 1))
    #expect(idx.previousBoundary(before: 1) == 0)
    #expect(idx.previousBoundary(before: 0) == 0)
    #expect(idx.spanIndex(at: 3) == 1)
    #expect(idx.spanIndex(at: 7.6) == nil)
}

@Test func simMoveIndexRunsToNextRetract() {
    let idx = SimulationMoveIndex(timeline: SimulationTimeline(toolpaths: [slot(), slot()], rapidRate: 180))
    #expect(idx.spans.filter(\.isRetract).count == 2)
    #expect(abs(idx.nextRetract(after: 0) - 7.6) < 1e-9)
    // After the first retract: the 2 s link rapid is level, so the next stop is the second retract.
    #expect(abs(idx.nextRetract(after: 7.6) - (7.6 + 2 + 7.6)) < 1e-9)
    #expect(abs(idx.nextRetract(after: 17.2) - idx.totalTime) < 1e-9)
}
