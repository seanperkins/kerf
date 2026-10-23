import CADCore
import Foundation
import Testing
@testable import CAMCore

/// Issue #96. The check used to sample the move every 0.9 R (R = tool radius + margin) and test the samples.
/// A move that grazes the grown corner of a zone crosses it along a chord of 2 * sqrt(R^2 - h^2), which is
/// shorter than that step for a big cutter, so a cutter overlapping the zone could pass between two samples.
private let bigCutter = Tool(name: "2 in surfacing bit", kind: .endMill, number: 1, diameter: 2, flutes: 2,
                             stepdown: 0.25, stepover: 1, feedRate: 200, plungeRate: 60)

private let corner = Vec2(10, 10)
/// A 10 x 10 clamp whose upper-right corner is `corner`.
private let clamp = KeepOutZone(name: "Clamp", outline: [Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)], height: 0.5)

/// A 10 in feed move along the diagonal running past `corner` with the tool centre `h` from it, starting
/// `shift` in along the line from where the closest point sits at 4.09 in.
private func graze(h: Double, shift: Double, zZero: ZZeroMode = .materialTop) -> ([Toolpath], MachineCoordinates) {
    let coords = MachineCoordinates(job: JobSetup(zZero: zZero))
    let n = Vec2(1, 1) / 2.0.squareRoot(), d = Vec2(1, -1) / 2.0.squareRoot()
    let foot = corner + n * h
    let a = foot - d * (4.0909 + shift), b = a + d * 10
    let z = coords.z(depth: 0.25)
    let tp = Toolpath(name: "Facing", kind: .profile, tool: bigCutter,
                      moves: [.rapid(to: Vec3(a, z: z)), .linear(to: Vec3(b, z: z), feed: 200)])
    return ([tp], coords)
}

@Test(arguments: [ZZeroMode.materialTop, .spoilboard])
func keepOutFlagsACutterGrazingAZoneCornerWhereverTheSamplesFall(zZero: ZZeroMode) {
    // The tool centre passes 0.95 in from the corner: the 1 in radius cutter overlaps the clamp by 0.05 in.
    for shift in stride(from: 0.0, through: 0.9, by: 0.05) {
        let (tps, coords) = graze(h: 0.95, shift: shift, zZero: zZero)
        let v = KeepOut.violations(tps, zones: [clamp], coords: coords, margin: 0.05, tolerance: 0.0005)
        #expect(v.count == 1, "missed at shift \(shift)")
        #expect(v.first?.isRapid == false)
    }
}

@Test func keepOutLeavesACutterClearOfTheMarginBand() {
    // 1.06 in is outside radius + margin (1.05 in), so no phase of the move may be flagged.
    for shift in stride(from: 0.0, through: 0.9, by: 0.1) {
        let (tps, coords) = graze(h: 1.06, shift: shift)
        #expect(KeepOut.violations(tps, zones: [clamp], coords: coords, margin: 0.05, tolerance: 0.0005).isEmpty)
    }
}

@Test func keepOutIgnoresAMoveThatNeverGoesBelowTheZoneTop() {
    let coords = MachineCoordinates(job: JobSetup())
    let above = coords.z(aboveTop: 0.6)    // zone top + margin is 0.55
    let tp = Toolpath(name: "Travel", kind: .profile, tool: bigCutter,
                      moves: [.rapid(to: Vec3(Vec2(-5, 5), z: above)), .rapid(to: Vec3(Vec2(15, 5), z: above))])
    #expect(KeepOut.violations([tp], zones: [clamp], coords: coords, margin: 0.05, tolerance: 0.0005).isEmpty)
}

@Test func keepOutFlagsAPlungeIntoTheZoneThatStartsAboveItsTop() {
    let coords = MachineCoordinates(job: JobSetup())
    let tp = Toolpath(name: "Plunge", kind: .profile, tool: bigCutter,
                      moves: [.rapid(to: Vec3(Vec2(5, 5), z: coords.z(aboveTop: 1))),
                              .linear(to: Vec3(Vec2(5, 5), z: coords.z(depth: 0.25)), feed: 60)])
    let v = KeepOut.violations([tp], zones: [clamp], coords: coords, margin: 0.05, tolerance: 0.0005)
    #expect(v.count == 1)
}
