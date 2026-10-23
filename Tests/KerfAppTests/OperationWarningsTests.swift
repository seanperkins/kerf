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

    @Test func theOtherToolsAnOperationCutsWithAreJudgedTooAndNamed() throws {
        let (p, _, lib) = try setup()
        var broken = lib
        let finish = try #require(lib.tools.first { $0.kind == .endMill })
        var big = try #require(lib.tools.first { $0.kind == .endMill && $0.diameter > finish.diameter + 1e-9 })   // a clearance tool is the larger one
        big.feedRate = 0; big.spindleRPM = 40000
        broken.upsert(big)
        let id = p.document.shapes[0].id
        var pocket = try #require(OperationFactory.make(kind: .pocket, project: p, library: broken, shapeIDs: [id]))
        guard case .pocket(var o) = pocket else { return }
        o.setup.toolID = finish.id
        o.params.clearanceToolIDs = [big.id]
        pocket = .pocket(o)
        let w = warnings(pocket, p, broken)
        #expect(w.count == 2 && w.allSatisfy { $0.hasPrefix("\(big.name): ") })
        #expect(w.contains { $0.contains("feed rate") } && w.contains { $0.contains("40000") })
        // The toolpath's override is for its primary tool, so the clearance tool's message does not offer it.
        #expect(w.first { $0.contains("feed rate") }?.contains("override") == false)
        // The same tool as the primary one is judged once; a missing tool is the picker's business.
        o.params.clearanceToolIDs = [finish.id, UUID()]
        #expect(warnings(.pocket(o), p, broken).isEmpty)
        // V-carve, inlay and relief name theirs too.
        let vbit = try #require(lib.tools.first { $0.kind == .vBit })
        var slow = broken
        var fixed = big
        fixed.spindleRPM = 18000
        slow.upsert(fixed)
        let vcarve = VCarveOperation(setup: OperationSetup(name: "V", toolID: vbit.id, shapeIDs: [id]),
                                     params: VCarveParameters(flatDepth: 0.2, flatClearanceToolID: big.id))
        #expect(warnings(.vcarve(vcarve), p, broken).contains { $0.hasPrefix("\(big.name): ") && $0.contains("feed rate") })
        let inlay = InlayOperation(setup: OperationSetup(name: "I", toolID: vbit.id, shapeIDs: [id]),
                                   params: InlayParameters(flatClearanceToolID: big.id))
        #expect(warnings(.inlay(inlay), p, broken).contains { $0.hasPrefix("\(big.name): ") })
        let relief = Relief3DOperation(setup: OperationSetup(name: "R", toolID: finish.id),
                                       params: Relief3DParameters(modelID: UUID(), roughing: RoughingSettings(toolID: big.id)))
        #expect(warnings(.relief3D(relief), p, broken).contains { $0.hasPrefix("\(big.name): ") })
        #expect(OperationWarnings.secondaryToolIDs(of: pocket, primary: finish, library: broken, material: nil, units: .inch) == [big.id])
    }

    @Test func aPocketJudgesOnlyTheClearanceToolsTheGeneratorWillUse() throws {
        let (p, _, lib) = try setup()
        let id = p.document.shapes[0].id
        let quarter = try #require(lib.tools.first { $0.kind == .endMill && abs($0.diameter - 0.25) < 1e-9 })
        var half = try #require(lib.tools.first { $0.kind == .endMill && abs($0.diameter - 0.5) < 1e-9 })
        var eighth = try #require(lib.tools.first { $0.kind == .endMill && abs($0.diameter - 0.125) < 1e-9 })
        half.feedRate = 0; eighth.feedRate = 0
        var broken = lib
        broken.upsert(half); broken.upsert(eighth)
        var op = PocketOperation(setup: OperationSetup(name: "P", toolID: quarter.id, shapeIDs: [id]), params: PocketParameters())
        // Smaller than the finish tool: skipped by the generator, so not judged. Larger: judged.
        op.params.clearanceToolIDs = [eighth.id]
        #expect(warnings(.pocket(op), p, broken).isEmpty)
        op.params.clearanceToolIDs = [half.id]
        #expect(warnings(.pocket(op), p, broken).contains { $0.hasPrefix("\(half.name): ") })
        // Each must be smaller than the one before: a second 1/2 in tool is skipped.
        var half2 = half
        half2.id = UUID(); half2.name = "Another half"
        broken.upsert(half2)
        op.params.clearanceToolIDs = [half.id, half2.id]
        let w = warnings(.pocket(op), p, broken)
        #expect(w.allSatisfy { $0.hasPrefix("\(half.name): ") } && !w.isEmpty)
    }

    @Test func onlyToolsThatMakeACutAreJudged() throws {
        let (p, _, lib) = try setup()
        var broken = lib
        let finish = try #require(lib.tools.first { $0.kind == .endMill })
        var other = try #require(lib.tools.first { $0.kind == .endMill && $0.id != finish.id })
        other.feedRate = 0
        broken.upsert(other)
        let id = p.document.shapes[0].id
        // A V-carve's clearance tool only cuts with a flat depth.
        let vbit = try #require(lib.tools.first { $0.kind == .vBit })
        var carve = VCarveOperation(setup: OperationSetup(name: "V", toolID: vbit.id, shapeIDs: [id]),
                                    params: VCarveParameters(flatDepth: 0.2, flatClearanceToolID: other.id))
        #expect(warnings(.vcarve(carve), p, broken).contains { $0.hasPrefix("\(other.name): ") })
        carve.params.flatDepth = nil
        #expect(warnings(.vcarve(carve), p, broken).isEmpty)
        // A relief: the rest tool only says what was finished before, the roughing tool cuts only when roughing is on,
        // and the primary tool cuts only when finishing is on or it also does the roughing.
        var bad = finish
        bad.feedRate = 0
        var reliefLib = lib
        reliefLib.upsert(bad)
        func relief(rough: Bool, roughTool: UUID?, finishing: Bool, rest: UUID?) -> AnyOperation {
            var params = Relief3DParameters(modelID: UUID(), roughing: RoughingSettings(isEnabled: rough, toolID: roughTool))
            params.finishing.isEnabled = finishing
            params.finishing.restToolID = rest
            return .relief3D(Relief3DOperation(setup: OperationSetup(name: "R", toolID: finish.id), params: params))
        }
        // Finish tool broken: judged when finishing runs, or when it also roughs; not when only another tool roughs.
        #expect(!warnings(relief(rough: false, roughTool: nil, finishing: true, rest: nil), p, reliefLib).isEmpty)
        #expect(!warnings(relief(rough: true, roughTool: nil, finishing: false, rest: nil), p, reliefLib).isEmpty)
        #expect(warnings(relief(rough: true, roughTool: other.id, finishing: false, rest: nil), p, reliefLib).isEmpty)
        // Roughing explicitly with the primary tool is the primary tool cutting.
        #expect(!warnings(relief(rough: true, roughTool: finish.id, finishing: false, rest: nil), p, reliefLib).isEmpty)
        #expect(warnings(relief(rough: false, roughTool: nil, finishing: false, rest: nil), p, reliefLib).isEmpty)
        // The rest tool is never judged; the roughing tool when roughing is on.
        #expect(warnings(relief(rough: false, roughTool: nil, finishing: true, rest: other.id), p, broken).isEmpty)
        #expect(warnings(relief(rough: true, roughTool: other.id, finishing: true, rest: nil), p, broken).contains { $0.hasPrefix("\(other.name): ") })
        #expect(warnings(relief(rough: false, roughTool: other.id, finishing: true, rest: nil), p, broken).isEmpty)
        // A merge has no tool of its own to judge, whatever its wrapper holds.
        var merged = MergeOperation(setup: OperationSetup(name: "M", toolID: other.id, shapeIDs: [id]), params: MergeParameters(children: []))
        merged.setup.toolID = other.id
        #expect(warnings(.merge(merged), p, broken).isEmpty)
    }

    @Test func theToolDatabaseJudgesSpindleSpeedByThePostAJobWouldStartWith() {
        let machines = BuiltInMachines.all, posts = BuiltInPosts.all
        // Out of the box: the Avid and its post.
        let avid = ToolDatabaseView.defaultPost(prefs: AppPreferences(), machines: machines, profiles: posts)
        #expect(avid.id == BuiltInPosts.avidMach4Inch.id && avid.minRPM == 6000 && avid.maxRPM == 24000)
        #expect(OperationWarnings.rpmProblem(1000, profile: avid) != nil)
        // The default machine decides the post when no post is chosen: GRBL runs lower speeds.
        var grbl = AppPreferences()
        grbl.defaultMachineID = BuiltInMachines.genericGRBL.id
        let g = ToolDatabaseView.defaultPost(prefs: grbl, machines: machines, profiles: posts)
        #expect(g.id == BuiltInPosts.genericGRBLMM.id)
        #expect(OperationWarnings.rpmProblem(1000, profile: g) == OperationWarnings.rpmProblem(1000, profile: BuiltInPosts.genericGRBLMM))
        // A machine's own spindle range replaces the post's.
        var spindle = BuiltInMachines.genericGRBL
        spindle.minRPM = 100; spindle.maxRPM = 500
        let own = ToolDatabaseView.defaultPost(prefs: grbl, machines: [spindle], profiles: posts)
        #expect(own.minRPM == 100 && own.maxRPM == 500)
        #expect(OperationWarnings.rpmProblem(300, profile: own) == nil && OperationWarnings.rpmProblem(1000, profile: own) != nil)
    }
}
