import CADCore
import Foundation
import Testing
@testable import CAMCore

private func piece(_ a: Vec3, _ b: Vec3, rate: Double = 60, stop: Bool = false) -> MotionPlanner.Piece {
    MotionPlanner.Piece(start: a, end: b, rate: rate, stopBefore: stop)
}

private let accel = MachineMotion(acceleration: 10, junctionDeviation: 0.002)

@Test func simPlannerInstantIsLengthOverFeed() {
    let d = MotionPlanner.durations([piece(Vec3(0, 0, 0), Vec3(10, 0, 0))], motion: .instant)
    #expect(abs(d[0] - 10) < 1e-12)
}

@Test func simPlannerTrapezoidAndTriangle() {
    // 1 in/s cruise, 10 in/s²: 0.1 s and 0.05 in to reach speed, same to stop.
    let long = MotionPlanner.durations([piece(Vec3(0, 0, 0), Vec3(10, 0, 0))], motion: accel)
    #expect(abs(long[0] - 10.1) < 1e-9)
    // Too short to reach cruise: peak sqrt(a·L).
    let short = MotionPlanner.durations([piece(Vec3(0, 0, 0), Vec3(0.01, 0, 0))], motion: accel)
    #expect(abs(short[0] - 2 * (0.1).squareRoot() / 10) < 1e-9)
}

@Test func simPlannerCollinearPiecesDoNotSlowDown() {
    let split = MotionPlanner.durations([piece(Vec3(0, 0, 0), Vec3(5, 0, 0)), piece(Vec3(5, 0, 0), Vec3(10, 0, 0))],
                                        motion: accel)
    #expect(abs(split.reduce(0, +) - 10.1) < 1e-9)
}

@Test func simPlannerCornersAndReversals() {
    let o = Vec3(0, 0, 0), x = Vec3(5, 0, 0)
    let straight = MotionPlanner.durations([piece(o, x), piece(x, Vec3(10, 0, 0))], motion: accel).reduce(0, +)
    let corner = MotionPlanner.durations([piece(o, x), piece(x, Vec3(5, 5, 0))], motion: accel).reduce(0, +)
    let reverse = MotionPlanner.durations([piece(o, x), piece(x, o)], motion: accel).reduce(0, +)
    let stopped = MotionPlanner.durations([piece(o, x), piece(x, Vec3(5, 5, 0), stop: true)], motion: accel)
        .reduce(0, +)
    #expect(corner > straight)
    #expect(corner < stopped)
    // A reversal is a full stop.
    #expect(abs(reverse - stopped) < 1e-9)
    #expect(abs(stopped - 2 * 5.1) < 1e-9)
}

@Test func simPlannerSlowsForSlowerNextMove() {
    // A fast move into a slow one must decelerate to the slow feed by the junction.
    let d = MotionPlanner.durations([piece(Vec3(0, 0, 0), Vec3(10, 0, 0), rate: 600),
                                     piece(Vec3(10, 0, 0), Vec3(20, 0, 0), rate: 60)], motion: accel)
    // 10 in/s cruise: 0.5 s / 5 in to accelerate from 0; decelerating 10→1 takes 0.9 s over 4.95 in.
    #expect(abs(d[0] - (1.0 + 0.9 + (10 - 5 - 4.95) / 10)) < 1e-9)
    // Second piece enters at 1 in/s: only the final stop costs time.
    #expect(abs(d[1] - (10 - 0.05 + 0.1)) < 1e-9)
}

@Test func simTimelineAccelerationAndScale() {
    let tool = Tool(name: "EM", kind: .endMill, number: 1, diameter: 0.25, stepdown: 0.1, stepover: 0.1,
                    feedRate: 60, plungeRate: 20)
    let tp = Toolpath(name: "line", kind: .profile, tool: tool, moves: [
        .rapid(to: Vec3(0, 0, 0)),
        .linear(to: Vec3(10, 0, 0), feed: 60),
        .dwell(seconds: 1),
        .linear(to: Vec3(20, 0, 0), feed: 60),
    ])
    #expect(abs(MachiningTimeEstimator.estimate([tp], rapidRate: 200, motion: .instant) - 21) < 1e-9)
    // The dwell is a full stop: two trapezoids.
    let a = MachiningTimeEstimator.estimate([tp], rapidRate: 200, motion: accel)
    #expect(abs(a - (2 * 10.1 + 1)) < 1e-9)
    var scaled = accel
    scaled.timeScale = 1.5
    #expect(abs(MachiningTimeEstimator.estimate([tp], rapidRate: 200, motion: scaled) - 1.5 * a) < 1e-9)
    // Tool-change allowances are not scaled.
    var other = tp
    other.tool = Tool(name: "EM2", kind: .endMill, number: 2, diameter: 0.25, stepdown: 0.1, stepover: 0.1,
                      feedRate: 60, plungeRate: 20)
    other.moves = [.linear(to: Vec3(20, 0, 0), feed: 60)]
    let two = MachiningTimeEstimator.estimate([tp, other], rapidRate: 200, toolChangeSeconds: 30, motion: scaled)
    #expect(abs(two - (1.5 * a + 30)) < 1e-9)
    // The timeline's steps tile the time axis.
    let tl = SimulationTimeline(toolpaths: [tp], rapidRate: 200, motion: accel)
    #expect(abs(tl.steps.last!.endTime - tl.totalTime) < 1e-9)
}
