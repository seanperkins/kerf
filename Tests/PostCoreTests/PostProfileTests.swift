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
    let tps = [a, b, a].enumerated().map { Toolpath(name: "\($0.offset)", kind: .profile, tool: $0.element) }
    #expect(ToolpathOrdering.groupedByTool(tps).map(\.name) == ["0", "2", "1"])
}
