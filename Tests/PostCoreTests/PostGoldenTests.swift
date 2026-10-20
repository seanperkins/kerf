import CADCore
import CAMCore
import Foundation
import Testing
@testable import PostCore

// Golden programs for `PostFixtures.postJob()` (inch document) in every shipped profile.
// Regenerate deliberately: any diff here changes what reaches the machine.

private func post(_ profile: PostProfile, zZero: ZZeroMode = .materialTop) throws -> String {
    try TemplatePostProcessor(profile: profile).post(PostFixtures.postJob(zZero: zZero))
}

private func expectSameLines(_ actual: String, _ expected: String) {
    #expect(actual.hasSuffix("\n"))
    let a = actual.dropLast().components(separatedBy: "\n"), e = expected.components(separatedBy: "\n")
    for (i, (x, y)) in zip(a, e).enumerated() where x != y {
        Issue.record("line \(i + 1): got '\(x)', expected '\(y)'")
        return
    }
    #expect(a.count == e.count)
}

@Test func goldenAvidMach4Inch() throws {
    expectSameLines(try post(BuiltInPosts.avidMach4Inch), goldenAvidInch)
}

@Test func goldenAvidMach4InchSpoilboardZero() throws {
    expectSameLines(try post(BuiltInPosts.avidMach4Inch, zZero: .spoilboard), goldenAvidInchSpoilboard)
}

@Test func goldenAvidMach4MM() throws {
    expectSameLines(try post(BuiltInPosts.avidMach4MM), goldenAvidMM)
}

@Test func goldenGenericGRBLMM() throws {
    expectSameLines(try post(BuiltInPosts.genericGRBLMM), goldenGRBL)
}

@Test func goldenProgramsPassTheValidator() throws {
    for p in BuiltInPosts.all {
        for mode in [ZZeroMode.materialTop, .spoilboard] {
            let job = PostFixtures.job(zZero: mode)
            let issues = GCodeValidator(profile: p, job: job, units: .inch).validate(gcode: try post(p, zZero: mode))
            #expect(issues.isEmpty, "\(p.id) \(mode): \(issues)")
        }
    }
}

private let goldenAvidInch = #"""
( Job: Golden )
( Post: Avid PRO6096 Mach4 [inch] v1.0 )
( Units: inches )
( Material: 12.0000 x 8.0000 x 0.7500 in - MDF )
( Z zero: material top [bottom at Z-0.7500] )
( XY origin: lower left )
( Safe Z: 0.2000  Home: X0.0000 Y0.0000 Z0.8000 )
( Tools: )
(   T1: 1/4" End Mill [2 flute] - End Mill, dia 0.2500 in )
(   T6: 60 deg V-Bit 1/2" - V-Bit, dia 0.5000 in )
( Toolpaths: )
(   Profile 1 [Profile, T1, S18000] )
(   V-Carve 1 [V-Carve, T6, S18000] )
( Estimated time: 0m 14s )
G20
G90
G17
G40
G49
G80
G94
M5
(Change to Tool: 1/4" End Mill [2 flute])
T1 M6
G0 Z0.2000
M3 S18000
G4 P3
( Toolpath: Profile 1 [Profile] )
G0 X1.0000 Y1.0000
G1 Z-0.2500 F30.0
X3.0000 F100.0
G3 X3.0000 Y3.0000 I0.0000 J1.0000
G1 X1.0000
Y1.0000
G0 Z0.2000
M5
(Change to Tool: 60 deg V-Bit 1/2")
T6 M6
G0 Z0.2000
M3 S18000
G4 P3
( Toolpath: V-Carve 1 [V-Carve] )
G0 X5.0000 Y5.0000
G1 Z-0.1000 F30.0
X6.0000 F80.0
G0 Z0.2000
G0 Z0.2000
M5
G0 X0.0000 Y0.0000
M30
"""#

private let goldenAvidInchSpoilboard = #"""
( Job: Golden )
( Post: Avid PRO6096 Mach4 [inch] v1.0 )
( Units: inches )
( Material: 12.0000 x 8.0000 x 0.7500 in - MDF )
( Z zero: spoilboard surface [top at Z0.7500] )
( XY origin: lower left )
( Safe Z: 0.9500  Home: X0.0000 Y0.0000 Z1.5500 )
( Tools: )
(   T1: 1/4" End Mill [2 flute] - End Mill, dia 0.2500 in )
(   T6: 60 deg V-Bit 1/2" - V-Bit, dia 0.5000 in )
( Toolpaths: )
(   Profile 1 [Profile, T1, S18000] )
(   V-Carve 1 [V-Carve, T6, S18000] )
( Estimated time: 0m 14s )
G20
G90
G17
G40
G49
G80
G94
M5
(Change to Tool: 1/4" End Mill [2 flute])
T1 M6
G0 Z0.9500
M3 S18000
G4 P3
( Toolpath: Profile 1 [Profile] )
G0 X1.0000 Y1.0000
G1 Z0.5000 F30.0
X3.0000 F100.0
G3 X3.0000 Y3.0000 I0.0000 J1.0000
G1 X1.0000
Y1.0000
G0 Z0.9500
M5
(Change to Tool: 60 deg V-Bit 1/2")
T6 M6
G0 Z0.9500
M3 S18000
G4 P3
( Toolpath: V-Carve 1 [V-Carve] )
G0 X5.0000 Y5.0000
G1 Z0.6500 F30.0
X6.0000 F80.0
G0 Z0.9500
G0 Z0.9500
M5
G0 X0.0000 Y0.0000
M30
"""#

private let goldenAvidMM = #"""
( Job: Golden )
( Post: Avid PRO6096 Mach4 [mm] v1.0 )
( Units: millimetres )
( Material: 304.800 x 203.200 x 19.050 mm - MDF )
( Z zero: material top [bottom at Z-19.050] )
( XY origin: lower left )
( Safe Z: 5.080  Home: X0.000 Y0.000 Z20.320 )
( Tools: )
(   T1: 1/4" End Mill [2 flute] - End Mill, dia 6.350 mm )
(   T6: 60 deg V-Bit 1/2" - V-Bit, dia 12.700 mm )
( Toolpaths: )
(   Profile 1 [Profile, T1, S18000] )
(   V-Carve 1 [V-Carve, T6, S18000] )
( Estimated time: 0m 14s )
G21
G90
G17
G40
G49
G80
G94
M5
(Change to Tool: 1/4" End Mill [2 flute])
T1 M6
G0 Z5.080
M3 S18000
G4 P3
( Toolpath: Profile 1 [Profile] )
G0 X25.400 Y25.400
G1 Z-6.350 F762
X76.200 F2540
G3 X76.200 Y76.200 I0.000 J25.400
G1 X25.400
Y25.400
G0 Z5.080
M5
(Change to Tool: 60 deg V-Bit 1/2")
T6 M6
G0 Z5.080
M3 S18000
G4 P3
( Toolpath: V-Carve 1 [V-Carve] )
G0 X127.000 Y127.000
G1 Z-2.540 F762
X152.400 F2032
G0 Z5.080
G0 Z5.080
M5
G0 X0.000 Y0.000
M30
"""#

private let goldenGRBL = #"""
( Job: Golden )
( Post: Generic GRBL [mm] v1.0 )
( Units: millimetres )
( Material: 304.800 x 203.200 x 19.050 mm - MDF )
( Z zero: material top [bottom at Z-19.050] )
( XY origin: lower left )
( Safe Z: 5.080  Home: X0.000 Y0.000 Z20.320 )
( Tools: )
(   T1: 1/4" End Mill [2 flute] - End Mill, dia 6.350 mm )
(   T6: 60 deg V-Bit 1/2" - V-Bit, dia 12.700 mm )
( Toolpaths: )
(   Profile 1 [Profile, T1, S18000] )
(   V-Carve 1 [V-Carve, T6, S18000] )
( Estimated time: 0m 15s )
G21
G90
G17
G94
M5
(Change to Tool: 1/4" End Mill [2 flute])
M0
G0 Z5.080
M3 S18000
G4 P3
( Toolpath: Profile 1 [Profile] )
G0 X25.400 Y25.400
G1 Z-6.350 F762
X76.200 F2540
G3 X76.200 Y76.200 I0.000 J25.400
G1 X25.400
Y25.400
G0 Z5.080
M5
(Change to Tool: 60 deg V-Bit 1/2")
M0
G0 Z5.080
M3 S18000
G4 P3
( Toolpath: V-Carve 1 [V-Carve] )
G0 X127.000 Y127.000
G1 Z-2.540 F762
X152.400 F2032
G0 Z5.080
G0 Z5.080
M5
G0 X0.000 Y0.000
M2
"""#
