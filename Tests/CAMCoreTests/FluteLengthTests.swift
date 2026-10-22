import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

/// Every operation kind warns when it cuts deeper than the tool's flutes (issue #8): the shank
/// would rub the wall, burn the material and can snap the bit. The check sits on the one path
/// every operation leaves through, so one table covers them all.
@Suite struct FluteLengthTests {
    /// The seeded tool with its flute length replaced.
    private static func tool(_ index: Int, flute: Double?) -> Tool {
        var t = ToolLibrary.seeded.tools[index]
        t.fluteLength = flute
        return t
    }

    /// Each kind cutting 0.5 in deep (the chamfer 0.2 in, as wide as its bit allows; the prism 1 in: a 90° bit across a 2 in square).
    private static let kinds: [(String, Int, (OperationSetup) -> AnyOperation, [Path])] = [
        ("profile", 0, { .profile(ProfileOperation(setup: $0, params: ProfileParameters(depth: DepthSettings(cutDepth: 0.5)))) }, [F.rect(1, 1, 4, 3)]),
        ("pocket", 0, { .pocket(PocketOperation(setup: $0, params: PocketParameters(depth: DepthSettings(cutDepth: 0.5)))) }, [F.rect(1, 1, 4, 3)]),
        ("drill", 8, { .drill(DrillOperation(setup: $0, params: DrillParameters(cutDepth: 0.5))) }, [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.125)]),
        ("holeMill", 0, { .holeMill(HoleMillOperation(setup: $0, params: HoleMillParameters(cutDepth: 0.5))) }, [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5)]),
        ("engrave", 5, { .engrave(EngraveOperation(setup: $0, params: EngraveParameters(depth: DepthSettings(cutDepth: 0.5)))) }, [F.rect(1, 1, 4, 3)]),
        ("chamfer", 6, { .chamfer(ChamferOperation(setup: $0, params: ChamferParameters(depth: 0.2))) }, [F.rect(1, 1, 4, 3)]),
        ("fluting", 3, { .fluting(FlutingOperation(setup: $0, params: FlutingParameters(depth: DepthSettings(cutDepth: 0.5)))) },
         [Path(points: [Vec2(1, 1), Vec2(9, 1)], closed: false)]),
        ("prism", 6, { .prism(PrismOperation(setup: $0, params: PrismParameters())) }, [F.rect(1, 1, 2, 2)]),
        ("vcarve", 5, { .vcarve(VCarveOperation(setup: $0, params: VCarveParameters(flatDepth: 0.5))) }, [F.rect(1, 1, 4, 4)]),
    ]

    @Test(arguments: [ZZeroMode.materialTop, .spoilboard])
    func everyOperationWarnsWhenItCutsDeeperThanTheFlutes(mode: ZZeroMode) throws {
        for (name, index, make, paths) in Self.kinds {
            let (seeded, ids) = F.document(paths, zZero: mode)
            // A 0.1 in flute: too short for every cut here. The same tool with a 2 in flute, or
            // no flute length recorded, says nothing.
            for (flute, warns) in [(0.1, true), (2.0, false), (nil, false)] as [(Double?, Bool)] {
                let tool = Self.tool(index, flute: flute)
                let ctx = CAMContext(document: seeded.document, tools: ToolLibrary(tools: [tool]))
                let tps = try make(OperationSetup(name: name, toolID: tool.id, shapeIDs: ids)).generate(in: ctx)
                let tp = try #require(tps.first, "\(name)")
                let depth = ctx.coords.depth(ofMachineZ: try #require(tp.minZ))
                #expect(depth > 0.15, "\(name) cut \(depth)")
                let w = tp.metadata["warning"] ?? ""
                #expect(w.contains("deep with a 0.1 in flute (\(tool.name)); the shank rubs the wall above the flutes") == warns,
                        "\(name) flute \(String(describing: flute)): \(w)")
                if warns { #expect(w.contains("cuts \(String(format: "%.4g", depth)) in deep"), "\(name): \(w)") }
            }
        }
    }

    @Test func fluteWarningJoinsTheOperationsOwnWarnings() throws {
        // A profile that already warns (its loop too short for four tabs) keeps that warning and
        // adds the flute note after it.
        let (seeded, ids) = F.document([F.rect(0, 0, 0.3, 0.3)])
        let tool = Self.tool(0, flute: 0.3)
        let ctx = CAMContext(document: seeded.document, tools: ToolLibrary(tools: [tool]))
        var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5))
        p.tabs = TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
        let tp = try AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "P", toolID: tool.id, shapeIDs: ids), params: p))
            .generate(in: ctx)[0]
        let w = try #require(tp.metadata["warning"])
        #expect(w.contains("fewer tabs than asked") && w.hasSuffix("the shank rubs the wall above the flutes"))
        #expect(w.contains("; cuts 0.5 in deep with a 0.3 in flute"))
    }

    @Test func cutBeyondFluteMeasuresFromTheMaterialTop() {
        var tool = ToolLibrary.seeded.tools[1]   // 1/8 in end mill, 0.5 in flute
        for mode in [ZZeroMode.materialTop, .spoilboard] {
            var job = JobSetup(); job.zZero = mode
            let coords = MachineCoordinates(job: job)
            func tp(_ depth: Double) -> Toolpath {
                Toolpath(name: "t", kind: .profile, tool: tool, moves: [.rapid(to: Vec3(0, 0, coords.safeZ)), .linear(to: Vec3(0, 0, coords.z(depth: depth)), feed: 30)])
            }
            let over = tp(0.6).cutBeyondFlute(coords: coords, tolerance: 0.0005)
            #expect(over.map { abs($0.depth - 0.6) < 1e-9 && $0.flute == 0.5 } == true)
            #expect(tp(0.5).cutBeyondFlute(coords: coords, tolerance: 0.0005) == nil)
            tool.fluteLength = nil
            #expect(tp(0.6).cutBeyondFlute(coords: coords, tolerance: 0.0005) == nil)
            tool.fluteLength = 0.5
        }
    }
}
