import CADCore
import CAMCore
import Foundation
import Testing
@testable import PostCore

@Test func builtInProfilesRoundTripJSON() throws {
    for p in BuiltInPosts.all {
        #expect(try PostProfile.fromJSON(p.toJSON()) == p)
    }
    #expect(Set(BuiltInPosts.all.map(\.id)).count == BuiltInPosts.all.count)
}

@Test func avidProfileMatchesMachineSpec() throws {
    let p = try #require(BuiltInPosts.profile(id: "avid-pro6096-mach4-inch"))
    #expect(p.units == .inch && p.unitsCode == "G20")
    #expect(p.fileExtension == "tap")
    #expect(p.preamble == ["G90", "G17", "G40", "G49", "G80", "G94"])
    #expect(p.toolChange == ["M5", "(Change to Tool: {TOOL_NAME})", "T{T} M6"])
    #expect(p.useToolLengthOffset == false)
    #expect(p.minRPM == 6000 && p.maxRPM == 24000)
    #expect(p.arcOutput == .incrementalIJ)
    #expect(p.footer.last == "M30")
    #expect(p.limits.xTravel == 60 && p.limits.yTravel == 96)
    #expect(BuiltInPosts.avidMach4MM.unitsCode == "G21")
}

@Test func commentsNeverNestParentheses() {
    #expect(BuiltInPosts.avidMach4Inch.comment("Tool (1/4)") == "( Tool [1/4] )")
}

@Test func groupingByToolIsStable() {
    let lib = ToolLibrary.seeded
    let a = lib.tools[0], b = lib.tools[1]
    let tps = [a, b, a].enumerated().map { Toolpath(name: "\($0.offset)", kind: .pocket, tool: $0.element) }
    #expect(ToolpathOrdering.groupedByTool(tps).map(\.name) == ["0", "2", "1"])
}

private func tp(_ name: String, _ kind: OperationKind, _ tool: Tool, op: UUID? = nil,
                at x: Double) -> Toolpath {
    Toolpath(name: name, operationID: op, kind: kind, tool: tool,
             moves: [.rapid(to: Vec3(x, 0, 0.5)), .linear(to: Vec3(x + 1, 1, -0.1), feed: 10)])
}

@Test func groupingNeverMovesAProfileAheadOfEarlierWork() {
    let lib = ToolLibrary.seeded
    let a = lib.tools[0], b = lib.tools[1]
    let tps = [tp("pocket", .pocket, a, at: 0), tp("vcarve", .vcarve, b, at: 50),
               tp("profile", .profile, a, at: 100)]
    #expect(ToolpathOrdering.groupedByTool(tps).map(\.name) == ["pocket", "vcarve", "profile"])
}

@Test func groupingKeepsOperationPassOrderAndOverlappingWork() {
    let lib = ToolLibrary.seeded
    let a = lib.tools[0], b = lib.tools[1]
    let op = UUID()
    // Same operation: clearance (b) then primary (a) must stay in that order.
    let sameOp = [tp("other", .pocket, a, at: 100), tp("clear", .pocket, b, op: op, at: 0),
                  tp("primary", .pocket, a, op: op, at: 0)]
    #expect(ToolpathOrdering.groupedByTool(sameOp).map(\.name) == ["other", "clear", "primary"])
    // Different operations that overlap in XY keep their order (rest machining).
    let overlap = [tp("p1", .pocket, a, at: 100), tp("rough", .pocket, b, at: 0),
                   tp("rest", .pocket, a, at: 0)]
    #expect(ToolpathOrdering.groupedByTool(overlap).map(\.name) == ["p1", "rough", "rest"])
    // Disjoint work from other operations may still be grouped.
    let disjoint = [tp("p1", .pocket, a, at: 100), tp("x", .pocket, b, at: 0),
                    tp("p2", .pocket, a, at: 50)]
    #expect(ToolpathOrdering.groupedByTool(disjoint).map(\.name) == ["p1", "p2", "x"])
}
