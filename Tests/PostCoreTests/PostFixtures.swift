import CADCore
import CAMCore
import Foundation
@testable import PostCore

/// A small, fully deterministic inch job: a 1/4" end-mill square-ish profile with an arc and
/// a V-bit engraving line, in material-top Z-zero, lower-left origin.
enum PostFixtures {
    static let endMill = ToolLibrary.seeded.tools[0]   // T1 1/4" end mill
    static let vBit = ToolLibrary.seeded.tools[5]      // T6 60° V-bit

    static func job(zZero: ZZeroMode = .materialTop) -> JobSetup {
        JobSetup(width: 12, height: 8, thickness: 0.75, xyOrigin: .lowerLeft, zZero: zZero,
                 safeZ: 0.2, homeZ: 0.8, home: Vec2(0, 0))
    }

    static func toolpaths(zZero: ZZeroMode = .materialTop) -> [Toolpath] {
        let mc = MachineCoordinates(job: job(zZero: zZero))
        let safe = mc.safeZ
        let d = mc.z(depth: 0.25)
        let profile = Toolpath(
            id: UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!,
            name: "Profile 1", kind: .profile, tool: endMill,
            moves: [
                .rapid(to: Vec3(1, 1, safe)),
                .linear(to: Vec3(1, 1, d), feed: 30),
                .linear(to: Vec3(3, 1, d), feed: 100),
                .arcCCW(to: Vec3(3, 3, d), center: Vec2(3, 2), feed: 100),
                .linear(to: Vec3(1, 3, d), feed: 100),
                .linear(to: Vec3(1, 1, d), feed: 100),
                .rapid(to: Vec3(1, 1, safe)),
            ])
        let vd = mc.z(depth: 0.1)
        let engrave = Toolpath(
            id: UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!,
            name: "V-Carve 1", kind: .vcarve, tool: vBit,
            moves: [
                .rapid(to: Vec3(5, 5, safe)),
                .linear(to: Vec3(5, 5, vd), feed: 30),
                .linear(to: Vec3(6, 5, vd), feed: 80),
                .rapid(to: Vec3(6, 5, safe)),
            ])
        return [profile, engrave]
    }

    static func postJob(zZero: ZZeroMode = .materialTop) -> PostJob {
        PostJob(name: "Golden", units: .inch, job: job(zZero: zZero), toolpaths: toolpaths(zZero: zZero),
                materialDescription: "MDF")
    }
}
