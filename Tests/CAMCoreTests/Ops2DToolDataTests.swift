import CADCore
import Foundation
import Testing
@testable import CAMCore

private typealias F = Ops2DFixture

private func library(withMaterialOn tool: Tool) -> ToolLibrary {
    var t = tool
    t.materials = [MaterialCuttingData(material: "MDF", spindleRPM: 16000, feedRate: 150, plungeRate: 45,
                                       stepdown: 0.25, stepover: 0.12)]
    var lib = ToolLibrary.seeded
    lib.upsert(t)
    return lib
}

private func feeds(_ tp: Toolpath) -> Set<Double> { Set(tp.moves.compactMap(\.feed)) }

@Test func ops2DToolMaterialDataReplacesCuttingData() throws {
    let lib = library(withMaterialOn: F.endMill)
    let t = lib.tool(id: F.endMill.id)!
    #expect(t.forMaterial("mdf").feedRate == 150)
    #expect(t.forMaterial("Oak").feedRate == F.endMill.feedRate)
    #expect(t.forMaterial(nil) == t)
    // Unit conversion scales the material data too.
    let mm = t.converted(to: .millimeter)
    #expect(abs(mm.materials![0].feedRate - 150 * 25.4) < 1e-9)
    #expect(abs(mm.forMaterial("MDF").stepdown - 0.25 * 25.4) < 1e-9)
}

@Test func ops2DJobMaterialDrivesToolpathFeedsAndPasses() throws {
    let lib = library(withMaterialOn: F.endMill)
    var (ctx, ids) = F.document([F.rect(0, 0, 2, 2)])
    ctx.tools = lib
    let op = AnyOperation.profile(ProfileOperation(setup: OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids),
                                                   params: ProfileParameters(depth: DepthSettings(cutDepth: 0.5))))
    let plain = try op.generate(in: ctx)[0]
    #expect(feeds(plain) == [F.endMill.feedRate, F.endMill.plungeRate])
    ctx.document.job.material = "MDF"
    let mdf = try op.generate(in: ctx)[0]
    #expect(feeds(mdf) == [150, 45])
    #expect(mdf.spindleRPM == 16000)
    // 0.5 deep at 0.25 per pass = 2 passes instead of 4.
    let depths = Set(mdf.moves.compactMap { $0.target?.z }.filter { $0 < -1e-9 }.map { ($0 * 1000).rounded() })
    #expect(depths == [-250, -500])
}

@Test func ops2DToolOverrideChangesOnlyThatToolpath() throws {
    let (ctx, ids) = F.document([F.rect(0, 0, 2, 2)])
    var setup = OperationSetup(name: "P", toolID: F.endMill.id, shapeIDs: ids)
    setup.toolOverride = ToolOverride(spindleRPM: 12000, feedRate: 80, stepdown: 0.5)
    let op = AnyOperation.profile(ProfileOperation(setup: setup, params: ProfileParameters(depth: DepthSettings(cutDepth: 0.5))))
    let tp = try op.generate(in: ctx)[0]
    #expect(feeds(tp) == [80, F.endMill.plungeRate])
    #expect(tp.spindleRPM == 12000)
    #expect(tp.tool.feedRate == 80)
    #expect(Set(tp.moves.compactMap { $0.target?.z }.filter { $0 < -1e-9 }) == [-0.5])
    // An empty override changes nothing.
    var plainSetup = setup
    plainSetup.toolOverride = ToolOverride()
    let plain = try AnyOperation.profile(ProfileOperation(setup: plainSetup)).generate(in: ctx)[0]
    #expect(plain.tool.feedRate == F.endMill.feedRate)
}

@Test func ops2DFeedsAndSpeedsArithmetic() {
    #expect(FeedsAndSpeeds.feedRate(rpm: 18000, flutes: 2, chipLoad: 0.004) == 144)
    #expect(abs(FeedsAndSpeeds.chipLoad(feedRate: 144, rpm: 18000, flutes: 2) - 0.004) < 1e-12)
    #expect(abs(FeedsAndSpeeds.rpm(feedRate: 144, flutes: 2, chipLoad: 0.004) - 18000) < 1e-9)
    #expect(FeedsAndSpeeds.chipLoad(feedRate: 100, rpm: 0, flutes: 2) == 0)
    #expect(abs(FeedsAndSpeeds.surfaceSpeed(diameter: 0.25, rpm: 18000, units: .inch) - .pi * 0.25 * 18000 / 12) < 1e-9)
    #expect(abs(FeedsAndSpeeds.surfaceSpeed(diameter: 6, rpm: 18000, units: .millimeter) - .pi * 6 * 18) < 1e-9)
}

@Test func ops2DToolAndJobDecodeWithoutNewFields() throws {
    var toolJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(F.endMill)) as! [String: Any]
    toolJSON.removeValue(forKey: "group")
    toolJSON.removeValue(forKey: "materials")
    let tool = try JSONDecoder().decode(Tool.self, from: JSONSerialization.data(withJSONObject: toolJSON))
    #expect(tool.group == nil && tool.materials == nil)
    let job = try JSONDecoder().decode(JobSetup.self, from: JSONEncoder().encode(JobSetup()))
    #expect(job.material == nil)
    let setup = try JSONDecoder().decode(OperationSetup.self,
                                         from: JSONEncoder().encode(OperationSetup(name: "A", toolID: UUID())))
    #expect(setup.toolOverride == nil)
}
