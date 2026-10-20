import CADCore
import CAMCore
import Foundation
import PostCore
import Testing

@Suite struct LayoutChecksTests {
    func doc(_ shapes: [(Double, Double, Double, Double)]) -> Document {
        var d = Document(job: JobSetup(width: 24, height: 18, thickness: 0.75))
        for (i, r) in shapes.enumerated() {
            d.add(Shape(name: "S\(i)", layerID: d.defaultLayerID,
                        paths: [ShapeFactory.rectangle(Rect2(x: r.0, y: r.1, width: r.2, height: r.3))]))
        }
        return d
    }

    @Test func vectorsInsideTheMaterialPass() {
        #expect(LayoutChecks.design(doc([(0, 0, 24, 18), (5, 5, 2, 2)])).isEmpty)
    }

    @Test func vectorsOutsideOrAcrossTheEdgeWarn() {
        let issues = LayoutChecks.design(doc([(30, 0, 2, 2), (23, 5, 2, 2), (5, 5, 2, 2)]))
        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.severity == .warning })
        #expect(issues.contains { $0.message.contains("entirely outside") && $0.message.contains("S0") })
        #expect(issues.contains { $0.message.contains("past the material edge") && $0.message.contains("S1") })
    }

    @Test func hiddenAndIgnoredLayersAreSkipped() {
        var d = doc([(30, 0, 2, 2)])
        let id = d.defaultLayerID
        #expect(LayoutChecks.design(d, ignoredLayers: [id]).isEmpty)
        d.layers[0].isVisible = false
        #expect(LayoutChecks.design(d).isEmpty)
    }

    @Test func materialLargerThanTheBedWarns() {
        let avid = BuiltInPosts.avidMach4Inch
        #expect(LayoutChecks.materialFits(JobSetup(width: 48, height: 96), units: .inch, profile: avid).isEmpty)
        #expect(LayoutChecks.materialFits(JobSetup(width: 62, height: 96), units: .inch, profile: avid).count == 1)
        // Millimetre job against the inch profile: 1600 mm > 60 in.
        #expect(LayoutChecks.materialFits(JobSetup(width: 1600, height: 900), units: .millimeter, profile: avid).count == 1)
    }

    @Test func toolpathsCuttingOffTheStockWarn() {
        let job = JobSetup(width: 24, height: 18, thickness: 0.75, xyOrigin: .center)
        let coords = MachineCoordinates(job: job)
        let tool = ToolLibrary.seeded.tools.first { $0.kind == .endMill }!.converted(to: .inch)
        func tp(_ pts: [Vec2]) -> Toolpath {
            var moves: [Move] = [.rapid(to: coords.machineAtSafeZ(pts[0]))]
            moves += pts.map { .linear(to: coords.machine($0, depth: 0.2), feed: 100) }
            moves.append(.rapid(to: coords.machineAtSafeZ(pts.last!)))
            return Toolpath(name: "T", kind: .profile, tool: tool, moves: moves)
        }
        // Tool centre on the edge or one radius beyond it: fine.
        #expect(LayoutChecks.toolpaths([tp([Vec2(0, 0), Vec2(24 + tool.radius, 18)])], job: job, units: .inch).isEmpty)
        // Two inches beyond the right edge.
        let issues = LayoutChecks.toolpaths([tp([Vec2(10, 5), Vec2(26, 5)])], job: job, units: .inch)
        #expect(issues.count == 1)
        #expect(issues[0].message.contains("outside the material"))
        // Rapids above the material may go anywhere.
        var safe = tp([Vec2(1, 1)])
        safe.moves.insert(.rapid(to: coords.machineAtSafeZ(Vec2(40, 40))), at: 0)
        #expect(LayoutChecks.toolpaths([safe], job: job, units: .inch).isEmpty)
    }
}
