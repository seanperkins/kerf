import CADCore
import Foundation
import Testing
@testable import CAMCore

private let endMill = ToolLibrary.seeded.tools[0]   // 1/4" end mill
private let ballNose = ToolLibrary.seeded.tools[3]  // 1/4" ball nose
private let vBit = ToolLibrary.seeded.tools[6]      // 90° V-bit

private func reliefOp(_ model: PlacedModel, tool: Tool, roughing: Bool = true, finishing: Bool = true,
                      allowance: Double = 0.02, stepover: Double = 0.04, angle: Double = 0) -> Relief3DOperation {
    Relief3DOperation(
        setup: OperationSetup(name: "Dome", toolID: tool.id),
        params: Relief3DParameters(modelID: model.id, resolution: 0.01,
                                   roughing: RoughingSettings(isEnabled: roughing, toolID: endMill.id,
                                                              allowance: allowance, passDepth: 0.25),
                                   finishing: FinishingSettings(isEnabled: finishing, stepover: stepover,
                                                                angle: angle)))
}

@Test func reliefPlacementCentresAndMapsDepth() {
    let (doc, model) = ReliefFixture.domeDocument()
    #expect(model.footprint.center.isApproximatelyEqual(to: Vec2(2, 2), tolerance: 1e-9))
    let depthOf = model.depthMapper()
    #expect(depthOf(1) == 0)
    #expect(depthOf(0) == 1)
    let fitted = ModelPlacement.place(model.mesh, name: "x", in: doc.job, fitting: Vec2(3, 1), depth: 0.5)
    #expect(abs(fitted.footprint.width - 1) < 1e-9)
    #expect(abs(fitted.footprint.height - 1) < 1e-9)
}

@Test func reliefHeightmapMatchesDome() throws {
    let (_, model) = ReliefFixture.domeDocument()
    let map = try ReliefHeightmap.rasterize(model, over: Rect2(x: 0.5, y: 0.5, width: 3, height: 3), cellSize: 0.05)
    // Each cell holds the mesh's shallowest point in its square. The mesh lies inside the
    // dome (within its facet sagitta), so the cell is bracketed by the dome's shallowest point in
    // the square (the corner nearest the axis) and the dome's depth at the cell centre.
    let half = map.cellSize / 2
    for j in 0..<map.rows {
        for i in 0..<map.columns {
            let p = map.position(i, j)
            let near = Vec2(min(max(2, p.x - half), p.x + half), min(max(2, p.y - half), p.y + half))
            #expect(map[i, j] >= ReliefFixture.domeDepth(near) - 1e-9)
            #expect(map[i, j] <= ReliefFixture.domeDepth(p) + 0.002)
        }
    }
    #expect(abs(map.minDepth) < 0.002)
    #expect(map.maxDepth == 1)
}

@Test func dropCutterBallOnFlatAndPeak() throws {
    var map = ReliefHeightmap(origin: .zero, cellSize: 0.01, columns: 101, rows: 101, baseDepth: 0.5)
    map[50, 50] = 0.1 // a single spike
    let ball = DropCutter(map: map, cutter: CutterProfile(shape: .ball, radius: 0.125))
    #expect(abs(ball.depth(at: Vec2(0.2, 0.2)) - 0.5) < 1e-12) // far from the spike: flat
    #expect(abs(ball.depth(at: Vec2(0.5, 0.5)) - 0.1) < 1e-12) // right on it
    let v = DropCutter(map: map, cutter: CutterProfile(shape: .vee(angle: 90, tipDiameter: 0), radius: 0.25))
    // Spike cell's nearest point is 0.095 away; on a 90° V that lifts the tip by 0.095.
    #expect(abs(v.depth(at: Vec2(0.6, 0.5)) - 0.195) < 1e-9)
}

@Test func reliefFinishingBallNeverGouges() throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let paths = try reliefOp(model, tool: ballNose, roughing: false).generate(in: ctx)
    let fin = try #require(paths.first)
    #expect(paths.count == 1)
    #expect(fin.tool.kind == .ballNose)
    #expect(ReliefFixture.followsConventions(fin, coords: ctx.coords))
    let samples = ReliefFixture.cutSamples(fin, coords: ctx.coords, step: 0.02)
    let gouge = ReliefFixture.maxGouge(samples, cutter: CutterProfile(tool: ballNose), surface: ReliefFixture.domeDepth)
    #expect(gouge < 0.004) // discretisation only; the faceted mesh sits inside the dome
    // It actually machines the dome: the tool reaches the apex and the base plane.
    // ...and does not leave much: an exact ball resting on the unit dome has its tip at
    // depth 1 - (sqrt((1 + R)^2 - r^2) - R).
    let rBall = ballNose.radius
    var leftover = 0.0
    for (p, d) in samples {
        let r = p.distance(to: Vec2(2, 2))
        guard r < 0.9 else { continue }
        let exact = 1 - (((1 + rBall) * (1 + rBall) - r * r).squareRoot() - rBall)
        leftover = max(leftover, exact - d)
    }
    #expect(leftover < 0.02)
    let depths = samples.map(\.1)
    #expect(depths.min()! < 0.01)
    #expect(abs(depths.max()! - 1) < 1e-6)
}

@Test func reliefFinishingVBitOnPyramidNeverGouges() throws {
    var doc = Document(units: .inch, job: JobSetup(width: 4, height: 4, thickness: 1))
    let mesh = ReliefFixture.pyramid(base: 2, height: 1, at: .zero)
    let model = ModelPlacement.place(mesh, name: "Pyramid", in: doc.job, depth: 0.5, zTop: 0.1)
    doc.models.append(model)
    // Exact pyramid: apex depth 0.1 at (2,2), base depth 0.5 at the 2" square's edges.
    func surface(_ p: Vec2) -> Double {
        let m = max(abs(p.x - 2), abs(p.y - 2))
        return m >= 1 ? 0.5 : 0.1 + 0.4 * m
    }
    let ctx = CAMContext(document: doc, tools: .seeded)
    let fin = try #require(reliefOp(model, tool: vBit, roughing: false, stepover: 0.08, angle: 45).generate(in: ctx).first)
    let samples = ReliefFixture.cutSamples(fin, coords: ctx.coords, step: 0.02)
    let gouge = ReliefFixture.maxGouge(samples, cutter: CutterProfile(tool: vBit), surface: surface)
    #expect(gouge < 0.003)
    #expect(samples.map(\.1).min()! < 0.12)
}

@Test func reliefRoughingLeavesAllowance() throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let allowance = 0.03
    let paths = try reliefOp(model, tool: ballNose, finishing: false, allowance: allowance).generate(in: ctx)
    let rough = try #require(paths.first)
    #expect(rough.tool.kind == .endMill)
    #expect(ReliefFixture.followsConventions(rough, coords: ctx.coords))
    let samples = ReliefFixture.cutSamples(rough, coords: ctx.coords, step: 0.02)
    // A flat cutter grown by the allowance, lowered by it, must stay above the dome.
    let fat = CutterProfile(shape: .flat, radius: endMill.radius + allowance)
    let gouge = ReliefFixture.maxGouge(samples.map { ($0.0, $0.1 + allowance) }, cutter: fat,
                                       surface: ReliefFixture.domeDepth)
    #expect(gouge < 0.002)
    // Levels respect the pass depth and roughing reaches close to the base.
    let levels = Set(rough.moves.filter { !$0.isRapid }.compactMap { $0.target?.z }.map { ($0 * 1e6).rounded() })
    #expect(levels.count >= 4)
    #expect(abs((rough.minZ ?? 0) - -(1 - allowance)) < 1e-6)
}

@Test func reliefRoughThenFinishOrderAndSpoilboardShift() throws {
    let (docTop, model) = ReliefFixture.domeDocument(zZero: .materialTop)
    let (docSpoil, _) = ReliefFixture.domeDocument(zZero: .spoilboard)
    var spoil = docSpoil
    spoil.models = docTop.models
    let op = reliefOp(model, tool: ballNose, stepover: 0.1)
    let top = try op.generate(in: CAMContext(document: docTop, tools: .seeded))
    let sb = try op.generate(in: CAMContext(document: spoil, tools: .seeded))
    #expect(top.map(\.name) == ["Dome (Roughing)", "Dome (Finishing)"])
    #expect(top.count == sb.count)
    for (a, b) in zip(top, sb) {
        #expect(a.moves.count == b.moves.count)
        for (ma, mb) in zip(a.moves, b.moves) {
            guard let ta = ma.target, let tb = mb.target else { continue }
            #expect(abs(tb.z - ta.z - 1.25) < 1e-9)
            #expect(ta.xy == tb.xy)
        }
    }
}

@Test func reliefBoundaryLimitsArea() throws {
    var (doc, model) = ReliefFixture.domeDocument()
    let square = Shape(layerID: doc.defaultLayerID, paths: [Path(points: [Vec2(1.5, 1.5), Vec2(2.5, 1.5),
                                                                         Vec2(2.5, 2.5), Vec2(1.5, 2.5)], closed: true)])
    doc.add(square)
    var op = reliefOp(model, tool: ballNose, roughing: false, stepover: 0.1)
    op.params.boundaryShapeIDs = [square.id]
    let ctx = CAMContext(document: doc, tools: .seeded)
    let fin = try #require(op.generate(in: ctx).first)
    let b = Rect2(points: fin.moves.filter { !$0.isRapid }.compactMap { $0.target?.xy })
    #expect(b.min.x >= 1.5 - 1e-6 && b.max.x <= 2.5 + 1e-6)
    #expect(b.min.y >= 1.5 - 1e-6 && b.max.y <= 2.5 + 1e-6)
}

@Test func reliefErrors() {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    var op = reliefOp(model, tool: ballNose)
    op.params.modelID = UUID()
    #expect(throws: CAMError.missingModel(op.params.modelID)) { try op.generate(in: ctx) }
    let none = reliefOp(model, tool: ballNose, roughing: false, finishing: false)
    #expect(throws: CAMError.self) { try none.generate(in: ctx) }
    var badRough = reliefOp(model, tool: ballNose)
    badRough.params.roughing.toolID = ballNose.id
    #expect(throws: CAMError.self) { try badRough.generate(in: ctx) }
}
