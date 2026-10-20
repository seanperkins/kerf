import CADCore
import Foundation
import Testing
@testable import CAMCore

private let job = JobSetup(width: 10, height: 10, thickness: 0.75)
private let coords = MachineCoordinates(job: job)

private func tool() -> Tool {
    Tool(name: "EM", kind: .endMill, number: 1, diameter: 0.25, stepdown: 0.1, stepover: 0.1,
         feedRate: 60, plungeRate: 20)
}

@Test func simLines3DSplitsRapidsAndFeedsInMaterialFrame() {
    let tp = Toolpath(name: "slot", kind: .profile, tool: tool(), moves: [
        .rapid(to: coords.machineAtSafeZ(Vec2(1, 1))),
        .linear(to: coords.machine(Vec2(1, 1), depth: 0.2), feed: 18),
        .linear(to: coords.machine(Vec2(7, 1), depth: 0.2), feed: 60),
        .linear(to: coords.machine(Vec2(7, 4), depth: 0.3), feed: 60),
        .rapid(to: coords.machineAtSafeZ(Vec2(7, 4))),
        .rapid(to: coords.machineAtSafeZ(Vec2(2, 2))),
    ])
    let lines = ToolpathLines3D(toolpaths: [tp], coords: coords)
    // The first rapid only sets the start; then one feed polyline and one rapid polyline.
    #expect(lines.polylines.count == 2)
    let feed = lines.polylines[0]
    #expect(!feed.isRapid)
    #expect(feed.points.count == 4)
    #expect(feed.points[1].distance(to: Vec3(1, 1, -0.2)) < 1e-9)
    #expect(feed.points[3].distance(to: Vec3(7, 4, -0.3)) < 1e-9)
    #expect(feed.points[0].z > 0) // starts at safe Z, above the material
    let rapid = lines.polylines[1]
    #expect(rapid.isRapid && rapid.points.count == 3)
    #expect(abs(lines.maxDepth - 0.3) < 1e-9)
    #expect(lines.segmentCount == 5)
}

@Test func simLines3DFlattensArcsAndKeepsToolpathIndex() {
    let start = coords.machine(Vec2(5, 3), depth: 0.1)
    let end = coords.machine(Vec2(5, 7), depth: 0.1)
    let a = Toolpath(name: "a", kind: .profile, tool: tool(), moves: [
        .rapid(to: start),
        .arcCCW(to: end, center: coords.machineXY(Vec2(5, 5)), feed: 60),
    ])
    let lines = ToolpathLines3D(toolpaths: [a, a], coords: coords)
    #expect(lines.polylines.count == 2)
    #expect(lines.polylines.map(\.toolpathIndex) == [0, 1])
    let arc = lines.polylines[0]
    #expect(arc.points.count > 8)
    for p in arc.points {
        #expect(abs(p.xy.distance(to: Vec2(5, 5)) - 2) < 0.01)
        #expect(abs(p.z + 0.1) < 1e-9)
    }
}
