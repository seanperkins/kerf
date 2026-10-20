import CADCore
import CAMCore
import Foundation
import PostCore
import Testing

@Suite struct LayoutKeepOutTests {
    let job = JobSetup(width: 24, height: 18, thickness: 0.75, safeZ: 0.5)
    var coords: MachineCoordinates { MachineCoordinates(job: job) }
    let tool = ToolLibrary.seeded.tools.first { $0.kind == .endMill }!.converted(to: .inch)

    func zone(height: Double) -> Fixtures.Zone {
        Fixtures.Zone(name: "Clamp 1", loops: [[Vec2(10, 10), Vec2(12, 10), Vec2(12, 12), Vec2(10, 12)]], height: height)
    }

    /// Rapid to `a` at safe Z, cut a line a→b at 0.1 deep, retract.
    func cut(_ a: Vec2, _ b: Vec2) -> Toolpath {
        Toolpath(name: "P", kind: .profile, tool: tool, moves: [
            .rapid(to: coords.machineAtSafeZ(a)),
            .linear(to: coords.machine(a, depth: 0.1), feed: 30),
            .linear(to: coords.machine(b, depth: 0.1), feed: 100),
            .rapid(to: coords.machineAtSafeZ(b)),
        ])
    }

    @Test func cuttingThroughAZoneIsAnError() {
        let issues = LayoutChecks.keepOut([cut(Vec2(5, 11), Vec2(15, 11))], zones: [zone(height: 0)], job: job, units: .inch)
        #expect(issues.count == 1)
        #expect(issues[0].severity == .error)
        #expect(issues[0].message.contains("keep-out zone 'Clamp 1'"))
    }

    @Test func theCutterRadiusCounts() {
        let r = tool.radius
        // Passing just below the zone: clear when the edge stays outside, an error when it reaches in.
        let clear = cut(Vec2(5, 10 - r - 0.01), Vec2(15, 10 - r - 0.01))
        #expect(LayoutChecks.keepOut([clear], zones: [zone(height: 0)], job: job, units: .inch).isEmpty)
        let touching = cut(Vec2(5, 10 - r * 0.5), Vec2(15, 10 - r * 0.5))
        #expect(LayoutChecks.keepOut([touching], zones: [zone(height: 0)], job: job, units: .inch).count == 1)
    }

    @Test func rapidsOverTallClampsAreErrorsButFlushZonesAreFine() {
        // Rapid at safe Z (0.5) from one side of the zone to the other.
        let hop = Toolpath(name: "H", kind: .profile, tool: tool, moves: [
            .rapid(to: coords.machineAtSafeZ(Vec2(5, 11))),
            .rapid(to: coords.machineAtSafeZ(Vec2(15, 11))),
        ])
        #expect(LayoutChecks.keepOut([hop], zones: [zone(height: 0)], job: job, units: .inch).isEmpty)
        let tall = LayoutChecks.keepOut([hop], zones: [zone(height: 1.5)], job: job, units: .inch)
        #expect(tall.count == 1)
        #expect(tall[0].message.contains("raise safe Z"))
    }
}
