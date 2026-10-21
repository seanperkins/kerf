import CADCore
import Foundation
import Testing
@testable import CAMCore

private let endMill = ToolLibrary.seeded.tools[0]   // 1/4" end mill
private let ballNose = ToolLibrary.seeded.tools[3]  // 1/4" ball nose

private func roughOp(_ model: PlacedModel, strategy: PocketStrategy, allowance: Double = 0.03,
                     resolution: Double = 0.02) -> Relief3DOperation {
    Relief3DOperation(
        setup: OperationSetup(name: "Dome", toolID: ballNose.id),
        params: Relief3DParameters(modelID: model.id, resolution: resolution,
                                   roughing: RoughingSettings(isEnabled: true, toolID: endMill.id, allowance: allowance,
                                                              passDepth: 0.25, strategy: strategy),
                                   finishing: FinishingSettings(isEnabled: false)))
}

private func cutLength(_ tp: Toolpath) -> Double {
    var total = 0.0
    var prev: Vec3?
    for m in tp.moves {
        guard let t = m.target else { continue }
        if !m.isRapid, let p = prev { total += (t - p).length }
        prev = t
    }
    return total
}

@Test func reliefErodedGridMatchesFlatDropCutter() {
    var map = ReliefHeightmap(origin: Vec2(0.3, -0.2), cellSize: 0.01, columns: 61, rows: 47, baseDepth: 0.5)
    var rng = SplitMix64(seed: 7)
    for k in map.depths.indices { map.depths[k] = 0.2 + 0.3 * rng.next() }
    let radius = 0.083
    let eroded = map.eroded(radius: radius)
    let cutter = DropCutter(map: map, cutter: CutterProfile(shape: .flat, radius: radius))
    for j in stride(from: 0, to: map.rows, by: 3) {
        for i in stride(from: 0, to: map.columns, by: 4) {
            #expect(abs(eroded[i, j] - cutter.depth(at: map.position(i, j))) < 1e-12)
        }
    }
}

@Test func reliefMarchingSquaresTracesDisc() {
    // Values = distance-to-centre style field: inside the 0.5 radius disc is >= threshold.
    var grid = ReliefHeightmap(origin: .zero, cellSize: 0.02, columns: 81, rows: 81, baseDepth: 0)
    for j in 0..<grid.rows {
        for i in 0..<grid.columns { grid[i, j] = 1 - grid.position(i, j).distance(to: Vec2(0.8, 0.8)) }
    }
    let loops = MarchingSquares.loops(grid, threshold: 0.5)
    #expect(loops.count == 1)
    let area = abs(Polygon2D.signedArea(loops[0]))
    #expect(abs(area - .pi * 0.25) < 0.01)
    // A ring (annulus) gives an outer loop and a hole.
    for j in 0..<grid.rows {
        for i in 0..<grid.columns {
            let r = grid.position(i, j).distance(to: Vec2(0.8, 0.8))
            grid[i, j] = r > 0.2 && r < 0.6 ? 1 : 0
        }
    }
    let ring = Polygon2D.region(fromLoops: MarchingSquares.loops(grid, threshold: 0.5))
    #expect(ring.count == 2)
    #expect(ring.filter { Polygon2D.signedArea($0) < 0 }.count == 1)
}

@Test(arguments: [PocketStrategy.offset, .raster(angle: 30, profilePass: true)])
func reliefRoughingStrategiesLeaveAllowance(strategy: PocketStrategy) throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let allowance = 0.03
    let rough = try #require(roughOp(model, strategy: strategy, allowance: allowance).generate(in: ctx).first)
    #expect(rough.metadata["pass"] == "roughing")
    #expect(rough.metadata["note"] == nil)
    #expect(ReliefFixture.followsConventions(rough, coords: ctx.coords))
    let samples = ReliefFixture.cutSamples(rough, coords: ctx.coords, step: 0.02)
    let fat = CutterProfile(shape: .flat, radius: endMill.radius + allowance)
    let gouge = ReliefFixture.maxGouge(samples.map { ($0.0, $0.1 + allowance) }, cutter: fat,
                                       surface: ReliefFixture.domeDepth)
    #expect(gouge < 0.002)
    #expect(abs((rough.minZ ?? 0) - -(1 - allowance)) < 1e-6)
    // It gets reasonably close to the dome: somewhere on the deepest level the cut runs within
    // allowance + a few cells of the dome's foot (radius 1 around the centre).
    let deepestLevel = samples.filter { abs($0.1 - (1 - allowance)) < 1e-6 }
    let nearest = deepestLevel.map { $0.0.distance(to: Vec2(2, 2)) }.min() ?? 9
    #expect(nearest < 1 + endMill.radius + allowance + 0.08)
    // Nothing leaves the footprint (the default boundary).
    for (p, _) in samples {
        #expect(p.x >= 1 - 1e-6 && p.x <= 3 + 1e-6 && p.y >= 1 - 1e-6 && p.y <= 3 + 1e-6)
    }
}

@Test func reliefRoughingOffsetDiffersFromRasterAndProfilePassAddsContour() throws {
    let (doc, model) = ReliefFixture.domeDocument()
    let ctx = CAMContext(document: doc, tools: .seeded)
    let offset = try #require(roughOp(model, strategy: .offset).generate(in: ctx).first)
    let raster = try #require(roughOp(model, strategy: .raster(angle: 0, profilePass: false)).generate(in: ctx).first)
    let rasterProfile = try #require(roughOp(model, strategy: .raster(angle: 0, profilePass: true)).generate(in: ctx).first)
    #expect(offset.moves != raster.moves)
    #expect(cutLength(rasterProfile) > cutLength(raster) + 4) // a contour of the dome per level
}
