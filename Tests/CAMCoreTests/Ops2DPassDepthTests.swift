import CADCore
import Foundation
import Testing
@testable import CAMCore

private func mils(_ d: [Double]) -> [Double] { d.map { ($0 * 1000).rounded() } }

@Test func ops2DPassDepthsEvenIsTheDefault() {
    let d = DepthSettings(cutDepth: 0.55, passDepth: 0.125)
    #expect(mils(d.passDepths(toolStepdown: 1)) == [110, 220, 330, 440, 550])
}

@Test func ops2DPassDepthsExactStepPutsTheRemainderLast() {
    var d = DepthSettings(startDepth: 0.05, cutDepth: 0.6, passDepth: 0.125)
    d.exactStep = true
    #expect(mils(d.passDepths(toolStepdown: 1)) == [175, 300, 425, 550, 600])
    // With a last pass thickness, roughing stops short of it.
    d.finalPassDepth = 0.02
    #expect(mils(d.passDepths(toolStepdown: 1)) == [175, 300, 425, 550, 580, 600])
    // An exact multiple needs no extra pass.
    var e = DepthSettings(cutDepth: 0.5, passDepth: 0.125)
    e.exactStep = true
    #expect(mils(e.passDepths(toolStepdown: 1)) == [125, 250, 375, 500])
}

@Test func ops2DPassDepthsCustomListIsSortedClampedAndEndsAtCutDepth() {
    var d = DepthSettings(startDepth: 0.1, cutDepth: 0.5)
    d.customPasses = [0.3, 0.05, 0.2, 0.3, 0.7, 0.5]
    #expect(mils(d.passDepths(toolStepdown: 0.01)) == [200, 300, 500])
    d.customPasses = []
    #expect(d.passDepths(toolStepdown: 0.2).count == 2)
}

@Test func ops2DProfileUsesCustomPasses() throws {
    let (ctx, ids) = Ops2DFixture.document([Ops2DFixture.rect(0, 0, 2, 2)])
    var depth = DepthSettings(cutDepth: 0.5)
    depth.customPasses = [0.3, 0.45]
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: Ops2DFixture.endMill.id, shapeIDs: ids),
                              params: ProfileParameters(depth: depth))
    let tp = try op.generate(in: ctx)[0]
    let depths = Set(Ops2DFixture.densePoints(tp.moves).map { (ctx.coords.depth(ofMachineZ: $0.z) * 1000).rounded() })
        .filter { $0 > 0 }
    #expect(depths == [300, 450, 500])
}

@Test func ops2DDepthSettingsDecodeWithoutNewFields() throws {
    let json = #"{"startDepth":0,"cutDepth":0.25,"finalPassDepth":0}"#
    let d = try JSONDecoder().decode(DepthSettings.self, from: Data(json.utf8))
    #expect(d.customPasses == nil && d.exactStep == nil)
}

/// A pass depth or stepdown of 0 or less is an error, not 750 000 passes.
@Test(arguments: [0.0, -0.1])
func ops2DNonPositivePassDepthIsRejected(step: Double) throws {
    let (ctx, ids) = Ops2DFixture.document([Ops2DFixture.rect(0, 0, 2, 2)])
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: Ops2DFixture.endMill.id, shapeIDs: ids),
                              params: ProfileParameters(depth: DepthSettings(cutDepth: 0.75, passDepth: step)))
    #expect(throws: CAMError.self) { try op.generate(in: ctx) }
    // The pocket and the tool's own stepdown are checked the same way.
    let pocket = PocketOperation(setup: OperationSetup(name: "K", toolID: Ops2DFixture.endMill.id, shapeIDs: ids),
                                 params: PocketParameters(depth: DepthSettings(cutDepth: 0.75, passDepth: step)))
    #expect(throws: CAMError.self) { try pocket.generate(in: ctx) }
    #expect(throws: CAMError.self) {
        try DepthSettings(cutDepth: 0.75).validatePassDepth(toolStepdown: step)
    }
    // The helper itself (also used for the form's preview) stays bounded.
    #expect(DepthSettings(cutDepth: 0.75, passDepth: step).passDepths(toolStepdown: 0.125).count == 1)
    #expect(DepthSettings(cutDepth: 0.75, passDepth: 1e-9).passDepths(toolStepdown: 0.125).count
                <= DepthSettings.maxComputedPasses)
}

/// A zig-zag ramp of length 0 (forced on open vectors) ramps at the max angle in two legs
/// instead of hundreds of thousands of legs.
@Test func ops2DZeroLengthZigzagRampIsBounded() throws {
    let open = Path(start: Vec2(1, 1), segments: [.line(to: Vec2(5, 1))], isClosed: false)
    let (ctx, ids) = Ops2DFixture.document(shapePaths: [open])
    var params = ProfileParameters(depth: DepthSettings(cutDepth: 0.75))
    params.side = .on
    params.tabs.isEnabled = false
    params.ramp = RampSettings(isEnabled: true, type: .smooth, length: 0, maxAngle: 10)
    let op = ProfileOperation(setup: OperationSetup(name: "P", toolID: Ops2DFixture.endMill.id, shapeIDs: ids),
                              params: params)
    let tp = try op.generate(in: ctx)[0]
    #expect(tp.moves.count < 2000, "\(tp.moves.count) moves")
    // Every ramp leg respects the max angle.
    var cur: Vec3?
    for m in tp.moves {
        guard let t = m.target else { continue }
        defer { cur = t }
        guard let s = cur, case .linear = m, s.xy.distance(to: t.xy) > 1e-6 else { continue }
        let slope = abs(t.z - s.z) / s.xy.distance(to: t.xy)
        #expect(slope <= tan(10.0 * .pi / 180) + 1e-6)
    }
}

@Test func ops2DPassDepthsOfASpanThatOverflowsAreNoneNotATrap() {
    // -1e308 to 1e308 are finite, their difference is not: the pass count was a NaN converted to Int.
    #expect(DepthSettings(startDepth: -1e308, cutDepth: 1e308).passDepths(toolStepdown: 0.1).isEmpty)
    #expect(DepthSettings(startDepth: 0, cutDepth: .infinity).passDepths(toolStepdown: 0.1).isEmpty)
    #expect(DepthSettings(startDepth: 0, cutDepth: .nan).passDepths(toolStepdown: 0.1).isEmpty)
}
