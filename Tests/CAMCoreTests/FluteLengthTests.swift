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

    private static let rubs = "the shank rubs the wall above the flutes"

    /// Each kind cutting 0.5 in deep where it can: the chamfer 0.2 in (as wide as its bit allows),
    /// the prism 0.25 in and the engraving about 0.43 in (bit-limited), the moulding its 0.25 in
    /// step. The builder gets the shapes' ids for operations that point at a second shape.
    private static let kinds: [(String, Int, (OperationSetup, [UUID]) -> AnyOperation, [Path])] = [
        ("profile", 0, { s, _ in .profile(ProfileOperation(setup: s, params: ProfileParameters(depth: DepthSettings(cutDepth: 0.5)))) }, [F.rect(1, 1, 4, 3)]),
        ("pocket", 0, { s, _ in .pocket(PocketOperation(setup: s, params: PocketParameters(depth: DepthSettings(cutDepth: 0.5)))) }, [F.rect(1, 1, 4, 3)]),
        ("drill", 8, { s, _ in .drill(DrillOperation(setup: s, params: DrillParameters(cutDepth: 0.5))) }, [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.125)]),
        ("holeMill", 0, { s, _ in .holeMill(HoleMillOperation(setup: s, params: HoleMillParameters(cutDepth: 0.5))) }, [ShapeFactory.circle(center: Vec2(3, 3), radius: 0.5)]),
        ("engrave", 5, { s, _ in .engrave(EngraveOperation(setup: s, params: EngraveParameters(depth: DepthSettings(cutDepth: 0.5)))) }, [F.rect(1, 1, 4, 3)]),
        ("chamfer", 6, { s, _ in .chamfer(ChamferOperation(setup: s, params: ChamferParameters(depth: 0.2))) }, [F.rect(1, 1, 4, 3)]),
        ("fluting", 3, { s, _ in .fluting(FlutingOperation(setup: s, params: FlutingParameters(depth: DepthSettings(cutDepth: 0.5)))) },
         [Path(points: [Vec2(1, 1), Vec2(9, 1)], closed: false)]),
        ("prism", 6, { s, _ in .prism(PrismOperation(setup: s, params: PrismParameters())) }, [F.rect(1, 1, 2, 2)]),
        ("vcarve", 5, { s, _ in .vcarve(VCarveOperation(setup: s, params: VCarveParameters(flatDepth: 0.5))) }, [F.rect(1, 1, 4, 4)]),
        ("inlay", 5, { s, _ in .inlay(InlayOperation(setup: s, params: InlayParameters(part: .female, pocketDepth: 0.5))) }, [F.rect(1, 1, 4, 4)]),
        ("straightInlay", 0, { s, _ in .straightInlay(StraightInlayOperation(setup: s, params: StraightInlayParameters(part: .female, pocketDepth: 0.5))) }, [F.rect(1, 1, 4, 3)]),
        ("texture", 0, { s, _ in .texture(TextureOperation(setup: s, params: TextureParameters(maxDepth: 0.5, spacing: 0.1, minStrokeLength: 1))) }, [F.rect(1, 1, 4, 4)]),
        ("moulding", 0, { s, ids in .moulding(MouldingOperation(setup: s, params: MouldingParameters(sectionShapeID: ids[1], side: .left, stepover: 0.05))) },
         [Path(points: [Vec2(1, 1), Vec2(9, 1)], closed: false),
          Path(points: [Vec2(20, 10), Vec2(20.5, 10), Vec2(20.5, 9.75), Vec2(21, 9.75)], closed: false)]),
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
                let tps = try make(OperationSetup(name: name, toolID: tool.id, shapeIDs: ids), ids).generate(in: ctx)
                let tp = try #require(tps.first, "\(name)")
                let depth = ctx.coords.depth(ofMachineZ: try #require(tp.minCutZ))
                #expect(depth > 0.15, "\(name) cut \(depth)")
                let w = tp.metadata["warning"] ?? ""
                #expect(w.contains("with a 0.1000 in flute (\(tool.name)); \(Self.rubs)") == warns, "\(name) flute \(String(describing: flute)): \(w)")
                if warns { #expect(w.contains("cuts \(String(format: "%.4f", depth)) in below the material top"), "\(name): \(w)") }
            }
        }
    }

    @Test func fluteWarningJoinsTheOperationsOwnWarnings() throws {
        // A profile that already warns (its loop too short for four tabs) keeps that warning and
        // adds the flute note after it, in the one wording every surface uses.
        let (seeded, ids) = F.document([F.rect(0, 0, 0.3, 0.3)])
        let tool = Self.tool(0, flute: 0.3)
        let ctx = CAMContext(document: seeded.document, tools: ToolLibrary(tools: [tool]))
        var p = ProfileParameters(depth: DepthSettings(cutDepth: 0.5))
        p.tabs = TabSettings(isEnabled: true, length: 0.25, thickness: 0.1, countPerPath: 4)
        let tp = try AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "P", toolID: tool.id, shapeIDs: ids), params: p))
            .generate(in: ctx)[0]
        let w = try #require(tp.metadata["warning"])
        #expect(w.contains("fewer tabs than asked"))
        #expect(w.hasSuffix("; cuts 0.5000 in below the material top with a 0.3000 in flute (\(tool.name)); \(Self.rubs)"))
    }

    @Test func mergeNotesEachChildOnce() throws {
        let (seeded, ids) = F.document([F.rect(1, 1, 4, 3)])
        let tool = Self.tool(0, flute: 0.1)
        let ctx = CAMContext(document: seeded.document, tools: ToolLibrary(tools: [tool]))
        let child = AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "Child", toolID: tool.id, shapeIDs: ids),
                                                          params: ProfileParameters(depth: DepthSettings(cutDepth: 0.5))))
        let merge = AnyOperation.merge(MergeOperation(setup: OperationSetup(name: "M", toolID: tool.id), params: MergeParameters(children: [child])))
        let w = try #require(try merge.generate(in: ctx)[0].metadata["warning"])
        #expect(w.components(separatedBy: Self.rubs).count == 2, Comment(rawValue: w))
    }

    @Test(arguments: [ZZeroMode.materialTop, .spoilboard])
    func startDepthCountsAsClearedMaterial(mode: ZZeroMode) throws {
        // A pocket from 0.5 to 0.9 in with a 0.75 in flute: the material above 0.5 in is already
        // gone, so the flutes reach. From 0.5 to 1.3 in they do not, and the note says what was
        // cleared. The toolpath carries the cleared depth for the export check.
        let (seeded, ids) = F.document([F.rect(1, 1, 4, 3)], zZero: mode)
        let tool = Self.tool(0, flute: 0.75)
        let ctx = CAMContext(document: seeded.document, tools: ToolLibrary(tools: [tool]))
        func pocket(to depth: Double) throws -> Toolpath {
            try AnyOperation.pocket(PocketOperation(setup: OperationSetup(name: "P", toolID: tool.id, shapeIDs: ids),
                                                    params: PocketParameters(depth: DepthSettings(startDepth: 0.5, cutDepth: depth)))).generate(in: ctx)[0]
        }
        let fits = try pocket(to: 0.9)
        #expect(fits.metadata["warning"] == nil && fits.clearedDepth == 0.5)
        let deep = try pocket(to: 1.3)
        #expect(deep.metadata["warning"] == "cuts 0.8000 in deeper than the 0.5000 in already cleared with a 0.7500 in flute (\(tool.name)); \(Self.rubs)")
    }

    @Test func projectedToolpathsMeasureFromTheCarvedSurface() throws {
        // A 0.05 in flute across the dome, projected onto it: the tool is 1 in below the material
        // top at the centre, but the relief above the surface is gone. A 0.5 in flute says nothing;
        // a 0.02 in flute is told the cut, not the drop.
        for (flute, warns) in [(0.5, false), (0.02, true)] {
            var (doc, model) = ReliefFixture.domeDocument()
            let line = Shape(layerID: doc.defaultLayerID, paths: [Path(points: [Vec2(0.6, 2), Vec2(3.4, 2)], closed: false)])
            doc.add(line)
            let tool = Self.tool(3, flute: flute)
            var setup = OperationSetup(name: "Flute", toolID: tool.id, shapeIDs: [line.id])
            setup.projectOntoModelID = model.id
            let op = AnyOperation.fluting(FlutingOperation(setup: setup, params: FlutingParameters(depth: DepthSettings(cutDepth: 0.05), ramp: .both, rampFraction: 0)))
            let tp = try op.generate(in: CAMContext(document: doc, tools: ToolLibrary(tools: [tool])))[0]
            let depth = MachineCoordinates(job: doc.job).depth(ofMachineZ: try #require(tp.minCutZ))
            #expect(depth > 0.9, "\(depth)")
            let w = tp.metadata["warning"] ?? ""
            #expect(w.contains("cuts 0.0500 in deeper than the") == warns && w.contains("with a 0.0200 in flute") == warns, Comment(rawValue: w))
        }
    }

    @Test func reliefWarnsFromTheMaterialTop() throws {
        // The relief itself carves the dome from the top: 1 in down with a 0.5 in flute.
        let (doc, model) = ReliefFixture.domeDocument()
        let tool = Self.tool(3, flute: 0.5)
        let p = Relief3DParameters(modelID: model.id, resolution: 0.05, roughing: RoughingSettings(isEnabled: false),
                                   finishing: FinishingSettings(isEnabled: true, stepover: 0.1, angle: 0))
        let tp = try AnyOperation.relief3D(Relief3DOperation(setup: OperationSetup(name: "R", toolID: tool.id), params: p))
            .generate(in: CAMContext(document: doc, tools: ToolLibrary(tools: [tool])))[0]
        #expect(tp.metadata["warning"]?.contains("below the material top with a 0.5000 in flute") == true)
    }

    @Test func cutBeyondFluteMeasuresCuttingMovesFromTheClearedDepth() {
        var tool = ToolLibrary.seeded.tools[1]   // 1/8 in end mill, 0.5 in flute
        for mode in [ZZeroMode.materialTop, .spoilboard] {
            var job = JobSetup(); job.zZero = mode
            let coords = MachineCoordinates(job: job)
            func tp(_ depth: Double, rapidOnly: Bool = false, cleared: Double? = nil) -> Toolpath {
                var t = Toolpath(name: "t", kind: .profile, tool: tool, moves: [.rapid(to: Vec3(0, 0, coords.safeZ)),
                    rapidOnly ? .rapid(to: Vec3(0, 0, coords.z(depth: depth))) : .linear(to: Vec3(0, 0, coords.z(depth: depth)), feed: 30)])
                t.clearedDepth = cleared
                return t
            }
            let over = tp(0.6).cutBeyondFlute(coords: coords, units: .inch, tolerance: 0.0005)
            #expect(over.map { abs($0.depth - 0.6) < 1e-9 && $0.flute == 0.5 && $0.cleared == 0 } == true)
            #expect(tp(0.5).cutBeyondFlute(coords: coords, units: .inch, tolerance: 0.0005) == nil)
            #expect(tp(0.6, rapidOnly: true).cutBeyondFlute(coords: coords, units: .inch, tolerance: 0.0005) == nil)
            #expect(tp(0.9, cleared: 0.5).cutBeyondFlute(coords: coords, units: .inch, tolerance: 0.0005) == nil)
            #expect(tp(1.1, cleared: 0.5).cutBeyondFlute(coords: coords, units: .inch, tolerance: 0.0005)?.cleared == 0.5)
            // The flute length follows the units the moves are in.
            let mmCoords = MachineCoordinates(job: job.scaled(by: 25.4))
            let mm = Toolpath(name: "t", kind: .profile, tool: tool, moves: [.linear(to: Vec3(0, 0, mmCoords.z(depth: 20)), feed: 30)])
            #expect(mm.cutBeyondFlute(coords: mmCoords, units: .millimeter, tolerance: 0.01)?.flute == 12.7)
            #expect(mm.cutBeyondFlute(coords: mmCoords, units: .millimeter, tolerance: 0.01)?.description.contains("cuts 20.000 mm below the material top with a 12.700 mm flute") == true)
            tool.fluteLength = nil
            #expect(tp(0.6).cutBeyondFlute(coords: coords, units: .inch, tolerance: 0.0005) == nil)
            tool.fluteLength = 0.5
        }
    }
}
