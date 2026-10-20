import CADCore
import Foundation
import Testing
@testable import PostCore

@Suite struct MachineDefinitionTests {
    @Test func builtInAvidMatchesItsPosts() {
        let m = BuiltInMachines.avidPRO6096
        #expect(m.limits == BuiltInPosts.avidMach4Inch.limits)
        // Applying the machine to its own posts changes nothing, so older jobs validate as before.
        #expect(m.applied(to: BuiltInPosts.avidMach4Inch) == BuiltInPosts.avidMach4Inch)
        let mm = m.applied(to: BuiltInPosts.avidMach4MM)
        #expect(abs(mm.limits.xTravel - 1524) < 1e-9 && abs(mm.limits.yTravel - 2438.4) < 1e-9)
        #expect(abs(mm.rapidRate - 15240) < 1e-9)
    }

    @Test func appliedConvertsUnitsAndKeepsDialect() {
        let m = MachineDefinition(id: "small", name: "Small", units: .millimeter,
                                  limits: MachineLimits(xTravel: 254, yTravel: 508, zTravel: 50.8, maxSpoilboardCut: 0.254),
                                  postIDs: [BuiltInPosts.avidMach4Inch.id], rapidRate: 2540, maxRPM: 18000)
        let p = m.applied(to: BuiltInPosts.avidMach4Inch)
        #expect(abs(p.limits.xTravel - 10) < 1e-9 && abs(p.limits.yTravel - 20) < 1e-9)
        #expect(abs(p.limits.zTravel - 2) < 1e-9 && abs(p.limits.maxSpoilboardCut - 0.01) < 1e-9)
        #expect(abs(p.rapidRate - 100) < 1e-9)
        #expect(p.maxFeed == BuiltInPosts.avidMach4Inch.maxFeed)  // nil keeps the post's value
        #expect(p.maxRPM == 18000 && p.minRPM == BuiltInPosts.avidMach4Inch.minRPM)
        #expect(p.preamble == BuiltInPosts.avidMach4Inch.preamble && p.units == .inch)
    }

    @Test func defaultPostFollowsDocumentUnits() {
        let m = BuiltInMachines.avidPRO6096
        #expect(m.defaultPostID(for: .inch, available: BuiltInPosts.all) == BuiltInPosts.avidMach4Inch.id)
        #expect(m.defaultPostID(for: .millimeter, available: BuiltInPosts.all) == BuiltInPosts.avidMach4MM.id)
        #expect(BuiltInMachines.genericGRBL.defaultPostID(for: .inch, available: BuiltInPosts.all)
                == BuiltInPosts.genericGRBLMM.id)
        #expect(m.defaultPostID(for: .inch, available: []) == nil)
    }

    @Test func jsonRoundTrip() throws {
        let m = BuiltInMachines.genericGRBL
        #expect(try MachineDefinition.fromJSON(m.toJSON()) == m)
        #expect(BuiltInMachines.avidPRO6096.envelopeDescription == "60 x 96 x 8 in")
    }

    @Test func validatorUsesMachineLimits() {
        // A 10 x 10 in machine rejects a 24 in long move that the Avid accepts.
        let small = MachineDefinition(id: "s", name: "S", units: .inch,
                                      limits: MachineLimits(xTravel: 10, yTravel: 10, zTravel: 4, maxSpoilboardCut: 0.05),
                                      postIDs: [])
        let gcode = "G20\nG90\nG0 Z0.5\nM3 S18000\nG0 X0 Y0\nG1 Z-0.1 F30\nG1 X24 F100\nG0 Z0.5\nM5\nM30\n"
        let job = JobSetup.defaults(for: .inch)
        let big = GCodeValidator(profile: BuiltInPosts.avidMach4Inch, job: job, units: .inch).validate(gcode: gcode)
        let tight = GCodeValidator(profile: small.applied(to: BuiltInPosts.avidMach4Inch), job: job, units: .inch)
            .validate(gcode: gcode)
        #expect(!big.contains { $0.severity == .error })
        #expect(tight.contains { $0.severity == .error })
    }
}
