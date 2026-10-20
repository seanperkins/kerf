import CADCore
import CAMCore
import Foundation
import Testing
@testable import PostCore

private func validate(_ gcode: String, zZero: ZZeroMode = .materialTop,
                      profile: PostProfile = BuiltInPosts.avidMach4Inch, units: LengthUnit = .inch) -> [GCodeIssue] {
    GCodeValidator(profile: profile, job: PostFixtures.job(zZero: zZero), units: units).validate(gcode: gcode)
}

/// Wraps motion lines in a well-formed program (units, spindle on, feed, footer).
private func program(_ body: String, spindle: Bool = true, safe: String = "0.2") -> String {
    """
    ( test )
    G20
    G90
    G0 Z\(safe)
    \(spindle ? "M3 S18000" : "")
    \(body)
    G0 Z\(safe)
    M5
    M30
    """
}

private func errors(_ issues: [GCodeIssue]) -> [String] { GCodeValidator.errors(in: issues).map(\.message) }

private func has(_ issues: [GCodeIssue], _ fragment: String, _ severity: GCodeIssue.Severity = .error) -> Bool {
    issues.contains { $0.severity == severity && $0.message.contains(fragment) }
}

@Test func cleanProgramHasNoIssues() {
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.25 F30\nX3 F100\nG3 X3 Y3 I0 J1\nG0 Z0.2"))
    #expect(issues.isEmpty, "\(issues)")
}

@Test func reportsTravelBeyondMachineLimits() {
    let issues = validate(program("G0 X0 Y0\nG0 X61 Y10"))
    #expect(has(issues, "X travel 61.0000 in exceeds"))
    #expect(!has(issues, "Y travel"))
}

@Test func arcExtentsCountTowardsTravel() {
    // Full circle of radius 30.5 around (30.5, 40): spans 61" in X — only visible via I/J.
    let issues = validate(program("G0 X0 Y40\nG1 Z-0.1 F30\nG2 X0 Y40 I30.5 J0 F100"))
    #expect(has(issues, "X travel"))
    #expect(!has(issues, "Y travel"))   // 61 < 96
}

@Test func reportsCutBelowAllowedDepthMaterialTopZero() {
    // 0.75 thick + 0.05 allowance: -0.79 is fine, -0.85 is not.
    #expect(validate(program("G0 X1 Y1\nG1 Z-0.79 F30")).isEmpty)
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.85 F30"))
    #expect(has(issues, "below the allowed depth Z-0.8000"))
    #expect(issues.first?.line == 7)
}

@Test func reportsCutBelowAllowedDepthSpoilboardZero() {
    #expect(validate(program("G0 X1 Y1\nG1 Z-0.04 F30", safe: "0.95"), zZero: .spoilboard).isEmpty)
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.1 F30", safe: "0.95"), zZero: .spoilboard)
    #expect(has(issues, "below the allowed depth Z-0.0500"))
}

@Test func maxCutThroughIsConfigurable() {
    var p = BuiltInPosts.avidMach4Inch
    p.limits.maxSpoilboardCut = 0.1
    #expect(validate(program("G0 X1 Y1\nG1 Z-0.84 F30"), profile: p).isEmpty)
}

@Test func reportsRapidThroughMaterial() {
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.1 F30\nG0 X2 Y2"))
    #expect(has(issues, "Rapid XY move inside the material"))
}

@Test func warnsOnRapidBelowSafeZAboveMaterial() {
    let issues = validate(program("G0 X1 Y1\nG0 Z0.05\nG0 X2"))
    #expect(errors(issues).isEmpty)
    #expect(has(issues, "below safe Z", .warning))
}

@Test func warnsOnRapidPlungeIntoMaterial() {
    let issues = validate(program("G0 X1 Y1\nG0 Z-0.1"))
    #expect(has(issues, "Rapid plunge", .warning))
}

@Test func reportsCuttingWithSpindleOff() {
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.1 F30", spindle: false))
    #expect(has(issues, "spindle off"))
    // Feed moves in the air without the spindle are not flagged.
    #expect(validate(program("G0 X1 Y1\nG1 Z0.1 F30", spindle: false)).isEmpty)
}

@Test func spindleStopMidProgramIsDetected() {
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.1 F30\nM5\nX2"))
    #expect(has(issues, "spindle off"))
}

@Test func reportsMissingFeed() {
    let issues = validate(program("G0 X1 Y1\nG1 Z-0.1\nX2\nX3"))
    #expect(has(issues, "without a feed rate"))
    #expect(issues.first { $0.message.contains("feed rate") }?.message.hasSuffix("(2 more)") == true)
}

@Test func reportsZeroFeedAndExcessiveFeed() {
    #expect(has(validate(program("G0 X1 Y1\nG1 Z-0.1 F0")), "zero or negative feed"))
    #expect(has(validate(program("G0 X1 Y1\nG1 Z-0.1 F900")), "exceeds the machine maximum", .warning))
}

@Test func reportsSpindleSpeedOutOfRange() {
    let issues = validate("G20\nM3 S30000\nM5\nM30")
    #expect(has(issues, "S30000 outside 6000"))
}

@Test func reportsArcRadiusMismatch() {
    let issues = validate(program("G0 X2 Y1\nG1 Z-0.1 F30\nG2 X0 Y1.5 I-1 J0"))
    #expect(has(issues, "radii differ"))
}

@Test func absoluteArcCentresFollowProfile() {
    var p = BuiltInPosts.avidMach4Inch
    p.arcOutput = .absoluteIJ
    #expect(validate(program("G0 X2 Y1\nG1 Z-0.1 F30\nG2 X0 Y1 I1 J1"), profile: p).isEmpty)
}

@Test func warnsOnMissingUnitsAndEnd() {
    let issues = validate("G0 Z0.2\nG0 X1 Y1")
    #expect(has(issues, "never sets units", .warning))
    #expect(has(issues, "M30/M2", .warning))
    #expect(errors(issues).isEmpty)
}

@Test func warnsWhenXYRapidPrecedesKnownZ() {
    let issues = validate("G20\nG0 X1 Y1\nM30")
    #expect(has(issues, "before the Z height is known", .warning))
}

@Test func checksInTheProgramsDeclaredUnits() {
    // Metric program with an inch profile and inch job: -19.5 mm (0.768") is fine, -21 mm is not.
    #expect(errors(validate("G21\nG0 Z5\nM3 S18000\nG0 X10 Y10\nG1 Z-19.5 F500\nG0 Z5\nM30")).isEmpty)
    let issues = validate("G21\nG0 Z5\nM3 S18000\nG0 X10 Y10\nG1 Z-21 F500\nG0 Z5\nM30")
    #expect(has(issues, "below the allowed depth"))
    #expect(has(issues, "differ from the profile", .warning))
}

@Test func parserHandlesCommentsLineNumbersAndCase() {
    let r = GCodeParser.parse("N10 g1 x1.5 (move) y-2 ; tail\n(only comment)\n%\nT1 M6")
    #expect(r.blocks.count == 2)
    #expect(r.blocks[0].value("X") == 1.5 && r.blocks[0].value("Y") == -2 && r.blocks[0].has("G", 1))
    #expect(r.blocks[1].line == 4 && r.blocks[1].has("M", 6))
    #expect(r.garbage.isEmpty)
}

// MARK: Toolpath-level validation

@Test func toolpathValidationFlagsDepthRapidsAndTravel() {
    let v = GCodeValidator(profile: BuiltInPosts.avidMach4Inch, job: PostFixtures.job(), units: .inch)
    #expect(v.validate(toolpaths: PostFixtures.toolpaths()).isEmpty)

    let bad = Toolpath(name: "bad", kind: .profile, tool: PostFixtures.endMill, moves: [
        .rapid(to: Vec3(0, 0, 0.2)),
        .linear(to: Vec3(0, 0, -1.0), feed: 30),        // through the spoilboard
        .rapid(to: Vec3(70, 0, -1.0)),                   // rapid in material, beyond X travel
    ])
    let issues = v.validate(toolpaths: [bad])
    #expect(has(issues, "below the allowed depth"))
    #expect(has(issues, "Rapid XY move inside the material"))
    #expect(has(issues, "X travel"))
}

@Test func toolpathValidationChecksRPMAndFeedAndUnits() {
    let mm = GCodeValidator(profile: BuiltInPosts.avidMach4Inch, job: PostFixtures.job().scaled(by: 25.4),
                            units: .millimeter)
    let tp = Toolpath(name: "fast", kind: .profile, tool: PostFixtures.endMill, spindleRPM: 26000, moves: [
        .rapid(to: Vec3(0, 0, 5)),
        .linear(to: Vec3(0, 0, -19.5), feed: 0),
        .rapid(to: Vec3(0, 0, 5)),
    ])
    let issues = mm.validate(toolpaths: [tp])
    #expect(has(issues, "S26000"))
    #expect(has(issues, "zero or negative feed"))
    #expect(!has(issues, "allowed depth"))
}

@Test func flagsInlayPocketAndPlugInOneProgram() {
    let tool = ToolLibrary.seeded.tools[5]
    func part(_ name: String) -> Toolpath {
        Toolpath(name: name, kind: .inlay, tool: tool,
                 moves: [.rapid(to: Vec3(1, 1, 0.5)), .linear(to: Vec3(1, 1, -0.1), feed: 20),
                         .rapid(to: Vec3(1, 1, 0.5))],
                 metadata: ["part": name])
    }
    let v = GCodeValidator(profile: BuiltInPosts.avidMach4Inch, job: PostFixtures.job(zZero: .materialTop), units: .inch)
    #expect(has(v.validate(toolpaths: [part("female"), part("male")]), "same program"))
    #expect(!has(v.validate(toolpaths: [part("female")]), "same program"))
}
