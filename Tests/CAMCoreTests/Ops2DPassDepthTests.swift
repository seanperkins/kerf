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
