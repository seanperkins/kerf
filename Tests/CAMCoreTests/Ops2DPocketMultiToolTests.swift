import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func multiTool(_ clearance: [UUID], finish: UUID = F.smallEndMill.id) throws -> ([Toolpath], CAMContext) {
    let (ctx, ids) = F.document([F.rect(0, 0, 4, 3)])
    let op = PocketOperation(setup: OperationSetup(name: "P", toolID: finish, shapeIDs: ids),
                             params: PocketParameters(depth: DepthSettings(cutDepth: 0.2), clearanceToolIDs: clearance))
    return (try op.generate(in: ctx), ctx)
}

@Test func ops2DPocketMultiToolCutsEachToolOnlyWhereNeeded() throws {
    let rect = Rect2(x: 0, y: 0, width: 4, height: 3)
    let (tps, ctx) = try multiTool([F.bigEndMill.id, F.endMill.id])
    #expect(tps.map(\.tool.id) == [F.bigEndMill.id, F.endMill.id, F.smallEndMill.id])
    #expect(tps.map(\.name) == ["P (clearance 1)", "P (clearance 2)", "P"])
    for tp in tps {
        #expect(F.conventionViolations(tp, coords: ctx.coords).isEmpty)
        #expect(abs(tp.minZ! + 0.2) < 1e-9)
        for p in F.densePoints(tp.moves) where p.z < -1e-9 {
            #expect(F.distanceToRectBoundary(p.xy, rect) >= tp.tool.radius - 0.0011)
        }
    }
    // The middle tool works only in the corners the 1/2" tool could not reach.
    let fullQuarter = try PocketOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id,
                                                                shapeIDs: ctx.document.shapes.map(\.id)),
                                          params: PocketParameters(depth: DepthSettings(cutDepth: 0.2))).generate(in: ctx)
    #expect(ToolpathStats(tps[1]).cutLength < ToolpathStats(fullQuarter[0]).cutLength / 4)
    let mid = F.densePoints(tps[1].moves).filter { $0.z < -1e-9 }.map(\.xy)
    let corners = [Vec2(0, 0), Vec2(4, 0), Vec2(4, 3), Vec2(0, 3)]
    #expect(!mid.isEmpty)
    #expect(mid.allSatisfy { p in corners.contains { $0.distance(to: p) < 0.6 } })
    #expect(corners.allSatisfy { c in mid.contains { $0.distance(to: c) < 0.2 } })
}

@Test func ops2DPocketMultiToolSkipsToolsOutOfOrder() throws {
    // The 1/2" tool comes after the 1/4" one, so it is ignored with a warning.
    let (tps, _) = try multiTool([F.endMill.id, F.bigEndMill.id])
    #expect(tps.map(\.tool.id) == [F.endMill.id, F.smallEndMill.id])
    #expect(tps.last!.metadata["warning"]?.contains("1 clearance tool(s) ignored") == true)
}

@Test func ops2DPocketMultiToolListOverridesLegacyClearanceTool() throws {
    var p = PocketParameters(clearanceToolID: F.bigEndMill.id)
    #expect(p.clearanceTools == [F.bigEndMill.id])
    p.clearanceToolIDs = []
    #expect(p.clearanceTools.isEmpty)
    let (single, _) = try multiTool([F.bigEndMill.id])
    #expect(single.map(\.name) == ["P (clearance)", "P"])
}
