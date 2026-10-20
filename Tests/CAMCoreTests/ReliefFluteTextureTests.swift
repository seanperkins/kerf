import CADCore
import Foundation
import Testing
@testable import CAMCore

private let ballNose = ToolLibrary.seeded.tools[3] // 1/4" ball nose, stepdown 0.1

private func docWithLine(_ pts: [Vec2], closed: Bool = false, zZero: ZZeroMode = .materialTop) -> (Document, Shape) {
    var doc = Document(units: .inch, job: JobSetup(width: 10, height: 10, thickness: 0.75, zZero: zZero))
    let shape = Shape(layerID: doc.defaultLayerID, paths: [Path(points: pts, closed: closed)])
    doc.add(shape)
    return (doc, shape)
}

private func cutPoints(_ tp: Toolpath, _ coords: MachineCoordinates) -> [(xy: Vec2, depth: Double)] {
    tp.moves.filter { !$0.isRapid }.compactMap { $0.target }.map { coords.material(fromMachine: $0) }
}

@Test func fluteRampsBothEndsLinear() throws {
    let (doc, line) = docWithLine([Vec2(1, 5), Vec2(5, 5)])
    let ctx = CAMContext(document: doc, tools: .seeded)
    let params = FlutingParameters(depth: DepthSettings(cutDepth: 0.25), ramp: .both, rampFraction: 0.25, smoothRamp: false)
    let tp = try #require(FluteToolpathGenerator.generate(
        setup: OperationSetup(name: "Flute", toolID: ballNose.id, shapeIDs: [line.id]), params: params, in: ctx).first)
    #expect(tp.kind == .fluting)
    #expect(ReliefFixture.followsConventions(tp, coords: ctx.coords))
    let pts = cutPoints(tp, ctx.coords)
    #expect(abs((pts.map(\.depth).max() ?? 0) - 0.25) < 1e-9)
    // Three passes (0.25 / 0.1 stepdown) alternating direction, no retract between them.
    #expect(tp.moves.filter(\.isRapid).count <= 4)
    // On the final pass: 0.5" into a 1" ramp the depth is half the cut depth; middle is full.
    let at = { (x: Double, d: Double) -> Bool in pts.contains { abs($0.xy.x - x) < 1e-9 && abs($0.depth - d) < 1e-9 } }
    #expect(at(1.5, 0.125))
    #expect(at(4.5, 0.125))
    #expect(pts.contains { $0.xy.x > 2 && $0.xy.x < 4 && abs($0.depth - 0.25) < 1e-9 })
    // Ends sit at the start depth.
    #expect(pts.filter { abs($0.xy.x - 1) < 1e-9 || abs($0.xy.x - 5) < 1e-9 }.allSatisfy { abs($0.depth) < 1e-9 })
}

@Test func fluteStartRampOnlyAndSmooth() throws {
    let (doc, line) = docWithLine([Vec2(0, 0), Vec2(4, 0)])
    let ctx = CAMContext(document: doc, tools: .seeded)
    let params = FlutingParameters(depth: DepthSettings(cutDepth: 0.1), ramp: .start, rampFraction: 0.5, smoothRamp: true)
    let tp = try #require(FluteToolpathGenerator.generate(
        setup: OperationSetup(name: "F", toolID: ballNose.id, shapeIDs: [line.id]), params: params, in: ctx).first)
    let pts = cutPoints(tp, ctx.coords)
    // Smooth (cosine) ramp: halfway up the 2" ramp the depth is half; the end is full depth.
    #expect(pts.contains { abs($0.xy.x - 1) < 1e-9 && abs($0.depth - 0.05) < 1e-9 })
    #expect(pts.contains { abs($0.xy.x - 4) < 1e-9 && abs($0.depth - 0.1) < 1e-9 })
    // Quarter of the ramp: (1 - cos(pi/4)) / 2 of the depth (smaller than linear).
    #expect(pts.contains { abs($0.xy.x - 0.5) < 1e-9 && abs($0.depth - 0.1 * (1 - cos(.pi / 4)) / 2) < 1e-9 })
}

@Test func fluteSpoilboardShiftsZ() throws {
    let pts = [Vec2(1, 1), Vec2(3, 2)]
    let (a, la) = docWithLine(pts)
    var (b, _) = docWithLine(pts, zZero: .spoilboard)
    b.shapes = a.shapes
    let setup = OperationSetup(name: "F", toolID: ballNose.id, shapeIDs: [la.id])
    let ta = try FluteToolpathGenerator.generate(setup: setup, params: FlutingParameters(), in: CAMContext(document: a, tools: .seeded))[0]
    let tb = try FluteToolpathGenerator.generate(setup: setup, params: FlutingParameters(), in: CAMContext(document: b, tools: .seeded))[0]
    #expect(ta.moves.count == tb.moves.count)
    for (ma, mb) in zip(ta.moves, tb.moves) {
        if let p = ma.target, let q = mb.target { #expect(abs(q.z - p.z - 0.75) < 1e-9) }
    }
}

@Test func fluteRejectsEmptySelection() {
    let ctx = CAMContext(document: Document(), tools: .seeded)
    #expect(throws: CAMError.noGeometry) {
        try FluteToolpathGenerator.generate(setup: OperationSetup(name: "F", toolID: ballNose.id),
                                            params: FlutingParameters(), in: ctx)
    }
}

@Test func textureIsDeterministicAndBounded() throws {
    let (doc, square) = docWithLine([Vec2(2, 2), Vec2(6, 2), Vec2(6, 5), Vec2(2, 5)], closed: true)
    let ctx = CAMContext(document: doc, tools: .seeded)
    let setup = OperationSetup(name: "Tex", toolID: ballNose.id, shapeIDs: [square.id])
    let params = TextureParameters(maxDepth: 0.05, spacing: 0.2, minStrokeLength: 0.4, maxStrokeLength: 1.2,
                                   angle: 30, variation: 0.6, seed: 42)
    let a = try TextureToolpathGenerator.generate(setup: setup, params: params, in: ctx)[0]
    let b = try TextureToolpathGenerator.generate(setup: setup, params: params, in: ctx)[0]
    #expect(a.moves == b.moves)
    var other = params
    other.seed = 43
    let c = try TextureToolpathGenerator.generate(setup: setup, params: other, in: ctx)[0]
    #expect(a.moves != c.moves)
    #expect(a.kind == .texture)
    #expect(ReliefFixture.followsConventions(a, coords: ctx.coords))

    let pts = cutPoints(a, ctx.coords)
    #expect(pts.count > 100)
    let inside = Rect2(x: 2, y: 2, width: 4, height: 3).insetBy(-1e-6)
    #expect(pts.allSatisfy { inside.contains($0.xy) })
    #expect(pts.allSatisfy { $0.depth <= 0.05 + 1e-9 })
    // Some strokes are shallower than the max (depth variation), none cut deeper than allowed.
    let deepest = pts.map(\.depth).max() ?? 0
    #expect(deepest > 0.02)
}

@Test func textureWithoutSelectionCoversMaterial() throws {
    var doc = Document(units: .inch, job: JobSetup(width: 3, height: 2, thickness: 0.5))
    doc.shapes = []
    let ctx = CAMContext(document: doc, tools: .seeded)
    let tp = try TextureToolpathGenerator.generate(setup: OperationSetup(name: "T", toolID: ballNose.id),
                                                   params: TextureParameters(), in: ctx)[0]
    let b = Rect2(points: cutPoints(tp, ctx.coords).map(\.xy))
    #expect(b.min.x >= -1e-6 && b.max.x <= 3 + 1e-6 && b.min.y >= -1e-6 && b.max.y <= 2 + 1e-6)
    #expect(b.width > 2)
}
