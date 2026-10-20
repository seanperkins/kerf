import CADCore
import Foundation
import Testing
@testable import CAMCore

private let ballNose = ToolLibrary.seeded.tools[3]  // 1/4" ball nose

private func fluteAcrossDome(_ doc: inout Document, depth: Double) -> FlutingOperation {
    let line = Shape(layerID: doc.defaultLayerID, paths: [Path(points: [Vec2(0.6, 2), Vec2(3.4, 2)], closed: false)])
    doc.add(line)
    return FlutingOperation(setup: OperationSetup(name: "Flute", toolID: ballNose.id, shapeIDs: [line.id]),
                            params: FlutingParameters(depth: DepthSettings(cutDepth: depth), ramp: .both, rampFraction: 0))
}

@Test func reliefProjectionFollowsSurfaceAtDepth() throws {
    var (doc, model) = ReliefFixture.domeDocument()
    let flute = fluteAcrossDome(&doc, depth: 0.05)
    var setup = flute.setup
    setup.projectOntoModelID = model.id
    let projected = AnyOperation.fluting(FlutingOperation(setup: setup, params: flute.params))
    let ctx = CAMContext(document: doc, tools: .seeded)
    let flat = try #require(AnyOperation.fluting(flute).generate(in: ctx).first)
    let tp = try #require(projected.generate(in: ctx).first)
    #expect(tp.metadata["projected"] == "Dome")
    #expect(flat.metadata["projected"] == nil)
    #expect(ReliefFixture.followsConventions(tp, coords: ctx.coords))
    // Without projection the flute is a flat 0.05 deep line; projected, it rides the dome.
    #expect(abs((flat.minZ ?? 0) - -0.05) < 1e-9)
    let samples = ReliefFixture.cutSamples(tp, coords: ctx.coords, step: 0.02).filter { abs($0.0.y - 2) < 1e-9 }
    let map = try ReliefHeightmap.rasterize(model, over: Rect2(x: 0.3, y: 1.6, width: 3.4, height: 0.8), cellSize: 0.01)
    let drop = DropCutter(map: map, cutter: CutterProfile(tool: ballNose))
    var checked = 0
    for (p, d) in samples where p.x > 1.25 && p.x < 2.75 {
        #expect(abs(d - (drop.depth(at: p) + 0.05)) < 0.006)
        checked += 1
    }
    #expect(checked > 20)
    // Never more than the requested depth into the dome (up to discretisation).
    let gouge = ReliefFixture.maxGouge(samples.map { ($0.0, $0.1 - 0.05) }, cutter: CutterProfile(tool: ballNose),
                                       surface: ReliefFixture.domeDepth, grid: 0.02)
    #expect(gouge < 0.006)
    // Over the apex the cut is near the top; at the dome's foot it is ~1.05 deep.
    #expect(samples.contains { abs($0.0.x - 2) < 0.03 && $0.1 < 0.1 })
    #expect(samples.contains { $0.1 > 0.95 })
}

@Test func reliefProjectionLinearisesArcsAndClampsRapids() throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let c = ctx.coords
    // Full clockwise circle of radius 1.5 around the dome (outside it: base plane at depth 1).
    let start = Vec2(3.5, 2)
    let moves: [Move] = [
        .rapid(to: c.machine(start, depth: -doc.job.safeZ)),
        .rapid(to: c.machine(start, depth: 0.5)), // a rapid below the top: must stop at the top
        .linear(to: c.machine(start, depth: 0.1), feed: 20),
        .arcCW(to: c.machine(start, depth: 0.1), center: c.machineXY(Vec2(2, 2)), feed: 50),
        .rapid(to: c.machine(start, depth: -doc.job.safeZ)),
    ]
    let tp = Toolpath(name: "Ring", kind: .profile, tool: ToolLibrary.seeded.tools[0], moves: moves)
    let out = try #require(ReliefProjection.project([tp], ontoModel: model.id, in: ctx).first)
    #expect(!out.moves.contains { $0.isArc })
    #expect(out.moves.filter(\.isRapid).compactMap { $0.target.map { c.depth(ofMachineZ: $0.z) } }.allSatisfy { $0 <= 1e-9 })
    let cuts = out.moves.filter { !$0.isRapid }.compactMap(\.target).map { c.material(fromMachine: $0) }
    #expect(cuts.count > 20)
    for p in cuts {
        #expect(abs(p.xy.distance(to: Vec2(2, 2)) - 1.5) < 0.001)
        #expect(abs(p.depth - 1.1) < 1e-6)
    }
    let missing = UUID()
    #expect(throws: CAMError.missingModel(missing)) { try ReliefProjection.project([tp], ontoModel: missing, in: ctx) }
}

@Test func operationSetupDecodesWithoutProjectionField() throws {
    let s = OperationSetup(name: "x", toolID: UUID())
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
    json.removeValue(forKey: "projectOntoModelID")
    let back = try JSONDecoder().decode(OperationSetup.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(back == s)
}
