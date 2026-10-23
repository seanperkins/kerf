import CADCore
import CAMCore
import Foundation
import PostCore
import Testing
@testable import KerfApp

/// Settings mistakes shown in the toolpath form before the export validator would catch them (issue #24).
@Suite struct OperationWarningsTests {
    let post = BuiltInPosts.avidMach4Inch

    /// A 0.75 in job with a profile on the first rectangle (0.5 in deep), and the library it cuts with.
    func setup(units: LengthUnit = .inch) throws -> (project: KerfProject, op: AnyOperation, library: ToolLibrary) {
        var p = AppTestSupport.project()
        p.document.job.thickness = 0.75
        let library = AppTestSupport.library().library
        let op = try #require(OperationFactory.make(kind: .profile, project: p, library: library, shapeIDs: [p.document.shapes[0].id]))
        p.operations = [op]
        return (p, op, library)
    }

    func warnings(_ op: AnyOperation, _ project: KerfProject, _ library: ToolLibrary, profile: PostProfile? = nil, units: LengthUnit = .inch) -> [String] {
        OperationWarnings.make(op, project: project, library: library, profile: profile ?? post, units: units)
    }

    func profile(_ op: AnyOperation, depth: Double? = nil, start: Double = 0, tabs: TabSettings? = nil) -> AnyOperation {
        guard case .profile(var o) = op else { return op }
        if let depth { o.params.depth.cutDepth = depth }
        o.params.depth.startDepth = start
        if let tabs { o.params.tabs = tabs }
        return .profile(o)
    }

    @Test func aPlainOperationHasNoWarnings() throws {
        let (p, op, lib) = try setup()
        #expect(warnings(profile(op, depth: 0.5), p, lib).isEmpty)
    }

    @Test func aCutPastTheSpoilboardAllowanceIsReportedButAThroughCutIsNot() throws {
        let (p, op, lib) = try setup()
        let allowance = post.limits.maxSpoilboardCut
        #expect(warnings(profile(op, depth: 0.75), p, lib).isEmpty)                         // through
        #expect(warnings(profile(op, depth: 0.75 + allowance), p, lib).isEmpty)             // as far as the machine allows
        let deep = warnings(profile(op, depth: 0.75 + allowance + 0.1), p, lib)
        #expect(deep.count == 1 && deep[0].contains("below the material bottom") && deep[0].contains("0.75"))
        // The allowance is the post's (machine's), not a constant.
        var generous = post
        generous.limits.maxSpoilboardCut = 0.5
        #expect(warnings(profile(op, depth: 1.2), p, lib, profile: generous).isEmpty)
        #expect(!warnings(profile(op, depth: 1.3), p, lib, profile: generous).isEmpty)
        // A cut projected onto a 3D model is measured from its surface, not the material top.
        guard case .profile(var projected) = op else { return }
        projected.setup.projectOntoModelID = UUID()
        projected.params.depth.cutDepth = 5
        #expect(warnings(.profile(projected), p, lib).isEmpty)
    }

    @Test func everyKindWithOneCutDepthIsChecked() throws {
        let (p, _, lib) = try setup()
        let id = p.document.shapes[0].id
        var checked = 0
        for kind in [OperationKind.pocket, .drill, .holeMill, .engrave, .fluting] {
            guard var op = OperationFactory.make(kind: kind, project: p, library: lib, shapeIDs: [id]) else { continue }
            switch op {
            case .pocket(var o): o.params.depth.cutDepth = 3; op = .pocket(o)
            case .drill(var o): o.params.cutDepth = 3; op = .drill(o)
            case .holeMill(var o): o.params.cutDepth = 3; op = .holeMill(o)
            case .engrave(var o): o.params.depth.cutDepth = 3; op = .engrave(o)
            case .fluting(var o): o.params.depth.cutDepth = 3; op = .fluting(o)
            default: continue
            }
            #expect(warnings(op, p, lib).contains { $0.contains("below the material bottom") }, "\(kind)")
            checked += 1
        }
        #expect(checked == 5)
        // A chamfer: its tip depth is the start depth plus how far the tip goes.
        var q = p
        let vbit = try #require(lib.tools.first { $0.kind == .vBit })
        q.tools = [vbit]
        let made = try #require(OperationFactory.make(kind: .chamfer, project: q, library: lib, shapeIDs: [id]))
        guard case .chamfer(var c) = made else { Issue.record("not a chamfer"); return }
        c.setup.toolID = vbit.id
        c.params = ChamferParameters(depth: 0.2, startDepth: 0.7)
        #expect(warnings(.chamfer(c), q, lib).contains { $0.contains("below the material bottom") })
        c.params = ChamferParameters(depth: 0.2, startDepth: 0.4)
        #expect(!warnings(.chamfer(c), q, lib).contains { $0.contains("below the material bottom") })
    }

    @Test func aMillimetreDocumentIsJudgedInMillimetres() throws {
        var (p, op, lib) = try setup()
        p.document.units = .millimeter
        p.document.job.thickness = 19
        // The same Avid inch post: its allowance is converted to mm.
        let allowanceMM = post.limits.maxSpoilboardCut * 25.4
        #expect(warnings(profile(op, depth: 19 + allowanceMM - 0.01), p, lib, units: .millimeter).filter { $0.contains("below") }.isEmpty)
        #expect(warnings(profile(op, depth: 19 + allowanceMM + 1), p, lib, units: .millimeter).contains { $0.contains("below the material bottom") })
    }

    @Test func aToolWithNoFeedPlungeOrDiameterIsReportedUntilTheOverrideFixesIt() throws {
        let (p, op, lib) = try setup()
        var broken = lib
        var tool = try #require(broken.tool(id: op.setup.toolID))
        tool.feedRate = 0; tool.plungeRate = -1; tool.diameter = 0
        broken.upsert(tool)
        let w = warnings(op, p, broken)
        #expect(w.contains { $0.contains("diameter") } && w.contains { $0.contains("feed rate") } && w.contains { $0.contains("plunge rate") })
        guard case .profile(var o) = op else { return }
        o.setup.toolOverride = ToolOverride(feedRate: 50, plungeRate: 20)
        let overridden = warnings(.profile(o), p, broken)
        #expect(overridden.count == 1 && overridden[0].contains("diameter"))
        // Not warned about when the numbers are fine, nor for a merge (it has no tool of its own).
        #expect(warnings(op, p, lib).isEmpty)
    }

    @Test func theSpindleSpeedIsJudgedAgainstThePostsRangeNotAConstant() throws {
        let (p, op, lib) = try setup()
        var fast = lib
        var tool = try #require(fast.tool(id: op.setup.toolID))
        tool.spindleRPM = 30000
        fast.upsert(tool)
        let w = warnings(op, p, fast)
        #expect(w.count == 1 && w[0].contains("30000") && w[0].contains(post.name))
        #expect(w[0].contains("\(Int(post.minRPM))") && w[0].contains("\(Int(post.maxRPM))"))
        var wide = post
        wide.minRPM = 1000; wide.maxRPM = 40000; wide.name = "Big spindle"
        #expect(warnings(op, p, fast, profile: wide).isEmpty)
        tool.spindleRPM = 500
        fast.upsert(tool)
        #expect(warnings(op, p, fast, profile: wide).count == 1)
        // The helper the Tool Database shares.
        #expect(OperationWarnings.rpmProblem(18000, profile: post) == nil)
        #expect(OperationWarnings.rpmProblem(0, profile: post) != nil)
        #expect(OperationWarnings.rpmProblem(.nan, profile: post) != nil)
        // A per-toolpath override counts.
        guard case .profile(var o) = op else { return }
        o.setup.toolOverride = ToolOverride(spindleRPM: 40000)
        #expect(warnings(.profile(o), p, lib).count == 1)
    }

    @Test func aTabAsTallAsTheCutIsReported() throws {
        let (p, op, lib) = try setup()
        let ok = TabSettings(isEnabled: true, length: 0.25, thickness: 0.125)
        #expect(warnings(profile(op, depth: 0.5, tabs: ok), p, lib).isEmpty)
        let tall = TabSettings(isEnabled: true, length: 0.25, thickness: 0.5)
        #expect(warnings(profile(op, depth: 0.5, tabs: tall), p, lib).contains { $0.contains("tabs") && $0.contains("as tall as the cut") })
        #expect(warnings(profile(op, depth: 0.4, tabs: ok), p, lib).isEmpty)
        // The cut is measured from the start depth.
        #expect(warnings(profile(op, depth: 0.5, start: 0.45, tabs: ok), p, lib).contains { $0.contains("tabs") })
        // Tabs that are off say nothing.
        var off = tall
        off.isEnabled = false
        #expect(warnings(profile(op, depth: 0.5, tabs: off), p, lib).isEmpty)
    }
}
